# adding ftp and assembly_report urls
import json
from collections import defaultdict
import re
import sys

jsonl_file = sys.argv[1]
for line in open(jsonl_file):
    data = json.loads(line.rstrip())
    acc = data["_GENOME_ACCESSION_"]

    # capitalise common name
    common_name = data.get("_COMMON_NAME_")
    if common_name:
        data["_COMMON_NAME_"] = common_name.capitalize()

    # update annotation name and provider for those from GenBank
    anno_name = data.get("_REFSEQ_ANN_NAME_", "") or ""
    anno_provider = data.get("_ANNOTATION_PROVIDER_NAME_", "") or ""
    if acc.startswith("GCF_"):
        # RefSeq
        data.update(
            _ANNOTATION_PROVIDER_NAME_ = "NCBI RefSeq",
            _ANNOTATION_SOURCE_ = "RefSeq",
            _ANNOTATION_SOURCE_SFX_ = "rs",
            _LOAD_GFF3_ANALYSIS_NAME_ = "refseq_import_visible",
        )
    else:
        # "GCA_" -- GenBank or community
        if anno_provider or anno_name.startswith("Annotation submitted by"):
            # assume GenBank
            data.update(
                _REFSEQ_ANN_NAME_ = "",
                _ANNOTATION_PROVIDER_NAME_ = data.get("_ASSEMBLY_PROVIDER_NAME_", ""),
                _ANNOTATION_SOURCE_ = "GenBank",
                _ANNOTATION_SOURCE_SFX_ = "gb",
                _LOAD_GFF3_ANALYSIS_NAME_ = "gff3_genes",
            )
        else:
            # assume community
            data.update(
                _REFSEQ_ANN_NAME_ = "",
                _ANNOTATION_PROVIDER_NAME_ = "COMMUNITY_PROVIDER_PLACEHOLDER",
                _ANNOTATION_SOURCE_ = "Community",
                _ANNOTATION_SOURCE_SFX_ = "cm",
                _LOAD_GFF3_ANALYSIS_NAME_ = "gff3_genes",
                _ANNOTATION_GFF3_ = "COMMUNITY_GFF3_PLACEHOLDER",
            )
    # report url
    ann_report_url = data.get("_REFSEQ_ANN_REPORT_URL_", "")
    if not ann_report_url:
        data.update(
            _REFSEQ_ANN_REPORT_URL_ = f"https://www.ncbi.nlm.nih.gov/datasets/genome/{acc}"
        )
    #
    sci_name = data["scientific_name"].lower()
    sci_name = re.sub(r"[^a-z0-9]+", " ", sci_name, flags=re.I).strip()
    abbr1, abbr2, *rest = sci_name.split(" ") + [""]
    data.update(
        _ABBREV_ = abbr1[:1] + abbr2[:5],
    )
    #
    print(json.dumps(data))
