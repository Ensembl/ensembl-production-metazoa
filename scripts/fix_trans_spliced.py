# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import re
import sys

from copy import deepcopy

def str2attrs(attrs_str: str) -> dict:
    if not str:
        return {}
    return {
        k:v for k, v in map(
            lambda pair: pair.split("="),
            attrs_str.strip().split(";")
        )
    }


def get_features(features_fn: str) -> (list, dict):
    seq_ids = []
    exon_ids = []
    features = {}

    if not features_fn:
        return exon_ids, features

    print(f"using {features_fn} to correct features affected with trans-splicing", file = sys.stderr)
    with open(features_fn) as features_file:
        # list of exons
        exons = []

        for line in features_file:
            if line.startswith("#"):
                continue
            seq, src, ftype, start, end, score, strand, phase, attrs_str, *rest = line.split("\t")
            start, end = int(start), int(end)
            strand_i = strand == "+" and 1 or strand == "-" and -1 or 0
            attrs_str = attrs_str.rstrip()
            attrs = str2attrs(attrs_str)
            if ftype == "CDS":
                # ignore as fo now
                continue
            # we can have multiple parents
            parents_s = attrs.get("Parent", "")
            parents = parents_s and parents_s.split(",") or []
            #
            ID = attrs.get("ID", "")
            rawID = ID
            if ftype == "exon" or not ID:
                ID = f"{seq}:{src}:{ftype}:{start}:{end}:{strand}:{parents_s}:{rawID}"
            #
            feature = {
                "ID" : ID,
                "rawID" : rawID,
                "raw": line,
                "seq" : seq,
                "ftype" : ftype,
                "start" : start,
                "end" : end,
                "strand" : strand,
                "strand_i" : strand_i,
                "attrs": attrs,
                "parents" : parents,
                "parents_s" : parents_s,
                "exon_strands" : [],
            }
            features[ID] = feature
            if ftype == "exon":
                exon_ids.append(ID)

    # be paranoined
    if len(exon_ids) != len(frozenset(exon_ids)):
        print(f"warnning: duplicated exon ids found...", file = sys.stderr)

    return exon_ids, features


def prepare_updates(exons: list, features_raw:dict) -> (set, dict):
    # CDS -> ... -> gene:
        #    update: min(start), max(end)
        #    rna strand -> 1 exon strand
    features = deepcopy(features_raw)
    #
    affected = set()
    upstream = list(filter(lambda exon_id: features.get(exon_id), exons))
    while upstream:
        feat_id = upstream.pop(0)
        feat = features.get(feat_id)
        # update parents if present
        parents = feat.get("parents", [])
        for parent_id in parents:
            parent = features.get(parent_id)
            if not parent:
                continue
            # fill the queue
            upstream.append(parent_id)
            affected.add(parent_id)
            # update
            parent["start"] = min(parent["start"], feat["start"])
            parent["end"] = max(parent["end"], feat["end"])
            if parent["strand"] not in "+-":
                # as for now, ignore rank of the exon
                parent["strand"] = feat["strand"]
            # store rank, part, strand for exons
            if feat["ftype"] == "exon":
                parent["exon_strands"].append([
                    feat.get("rank", feat.get("part")),
                    feat.get("strand")
                ])
        # fix exon parents' strand based on the exon rank
        exon_strands = filter(lambda x: x[0], feat.get("exon_strands", []))
        exon_strands_sorted = sorted(exon_strands, key = lambda p: int(p[0]))
        if exon_strands_sorted:
            feat["strand"] = exon_strands_sorted[0][1]

    # get updated and fix start, end types
    updates = { k : features[k] for k in affected }
    for k in updates.keys():
        updates[k]["start"] = str(updates[k]["start"])
        updates[k]["end"] = str(updates[k]["end"])
    # get affected regions
    regions = frozenset([v["seq"] for v in features.values() ] )

    return regions, updates


def filter_gff3(regions: set, updates:dict) -> set:
    affected_tr_ids = set()

    # internals
    types_of_interest = frozenset([v["ftype"] for v in updates.values()])
    print(f"feature types of interest: {types_of_interest}", file=sys.stderr)
    seen_genes = set()

    # iterate: stdin -> stdout
    for line in sys.stdin:
        if line.startswith("#"):
            sys.stdout.write(line)
            continue
        # split otherwise
        seq, rest = line.split("\t", 1)
        if seq not in regions:
            sys.stdout.write(line)
            continue
        # fix
        seq, src, ftype, start, end, score, strand, phase, attrs_str, *rest = line.split("\t")
        # no start, end to int conversion
        attrs_str = attrs_str.rstrip()
        attrs = str2attrs(attrs_str)
        # fix rank for exons
        if ftype == "exon":
            part = attrs.get("part", None)
            if "rank" not in attrs and part:
                attrs_str = attrs_str + f";rank={part}"
            out = "\t".join([seq, src, ftype, start, end, score, strand, phase, attrs_str])
            print(out, file = sys.stdout)
            continue
        # fix other bits
        if ftype in types_of_interest:
            ID = attrs.get("ID", "")
            # skip duplicated genes
            if ftype == "gene" and ID in seen_genes:
                continue
            else:
                seen_genes.add(ID)
            # update start, end, strand
            update = updates.get(ID, {})
            if update and ftype != "gene":
                # store IDs of the mRNA or alike
                affected_tr_ids.add(ID)
            start = update.get("start", start)
            end = update.get("end", end)
            strand = update.get("strand", strand)
            out = "\t".join([seq, src, ftype, start, end, score, strand, phase, attrs_str])
            print(out, file = sys.stdout)
            continue
        # just pass through the rest
        sys.stdout.write(line)

    return affected_tr_ids


def report_tr_spliced_transcripts(affected:set, trim_expr: str) -> None:
    if not affected:
        return

    pattern_list = []
    if trim_expr:
        for pair in trim_expr.split(","):
            if not pair:
                continue
            ftype, pfx, *rest = f"{pair}:".split(":")
            is_pattern = ftype.endswith("!")
            ftype = ftype.rstrip("!")
            ftype_l = ftype.lower()
            if ftype == "ANY" or ftype_l.endswith("rna") or ftype_l.endswith("transcript"):
                if not is_pattern:
                    pfx = re.escape(pfx)
                pattern_list.append(pfx)

    out_list = ",".join(sorted(affected))
    print(f"raw TR_TRANS_SPLICED: {out_list}", file=sys.stderr)

    if pattern_list:
        pattern = "|".join(pattern_list)
        pattern = re.compile(f"^({pattern})")
        print(f"using {pattern} to remove prefices", file=sys.stderr)
        affected = [ re.sub(pattern, "", s) for s in affected ]

    out_list = ",".join(sorted(set(affected)))
    print(f"#CONF\tTR_TRANS_SPLICED\t{out_list}", file=sys.stderr)


def get_args() -> None:
    parser = argparse.ArgumentParser()
    # various configs and maps
    parser.add_argument("--features_of_interest", metavar="trans_spliced_bits.gff3",
                        required=False,
                        type=str,
                        help="files with gff3 features related to trans-splicing")
    parser.add_argument("--pfx_trims",
                        metavar=r"ANY!:.+\|,ANY:id-,ANY:gene-,ANY:rna-,ANY:mrna-,cds:cds-,exon:exon-",
                        default=r"",
                        required=False,
                        type=str,
                        help="A ',' joined list of 'feature:text_prefix' or 'feature!:pattern' pattern fot prefix removal")
    args = parser.parse_args()
    return args


def main(*args, **kwargs):
    args = get_args()

    exon_ids, features = get_features(args.features_of_interest)
    affected_regions, updates = prepare_updates(exon_ids, features)
    affected_tr_ids = filter_gff3(affected_regions, updates)
    report_tr_spliced_transcripts(affected_tr_ids, args.pfx_trims)


# main
if __name__ == "__main__":
    # execute only if beeing run as a script
    main()
