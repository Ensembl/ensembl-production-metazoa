import argparse
import re
import os
import sys

from os.path import join as pj


def get_args():
    parser = argparse.ArgumentParser()
    # various configs and maps
    parser.add_argument(
        "--template",
        metavar="refseq.tmpl",
        required=True,
        type=argparse.FileType("rt", encoding="UTF-8"),
        help="template file to use",
    )
    parser.add_argument(
        "--param_table",
        metavar="_species.lst",
        required=True,
        type=argparse.FileType("rt", encoding="UTF-8"),
        help="species data as a tsv file with header",
    )
    parser.add_argument(
        "--output_dir",
        metavar="_species.lst",
        required=False,
        type=str,
        default=".",
        help="directory to write results to",
    )
    parser.add_argument(
        "--out_file_pfx",
        metavar="rs_",
        required=False,
        type=str,
        default="",
        help="directory to write results to",
    )
    parser.add_argument(
        "--keep_empty_values",
        required=False,
        action="store_true",
        default=False,
        help="keep rows with empty cells",
    )
    args = parser.parse_args()
    return args


def load_species_data(infile, keep_empty_values=False):
    out = []
    header = None
    for line in infile:
        line = re.sub("#.*$", "", line)
        if not line.strip():
            continue
        if not header:
            header = list(map(lambda s: s.strip(), line.strip().split()))
            continue
        conf_raw = list(map(lambda s: s.strip(), line.strip().split("\t"))) + [
            ""
        ] * len(header)
        conf = dict(zip(header, conf_raw[: len(header)]))
        if "" in conf.values():
            print(f"# warning: incomplete configuration: {conf}", file=sys.stderr)
            if not keep_empty_values:
                continue
        # print(f"configuration: {conf}" , file = sys.stderr)
        out.append(conf)
    return out


def fill_template(
    template: str, conf: dict, name_field: str, dir_path: str, file_pfx: str = ""
):
    name = conf.get(name_field, name_field)
    filename = pj(dir_path, file_pfx + name)
    with open(filename, "w") as outfile:
        print(f"# creating '{name}' meta file", file=sys.stderr)
        template = str(template)
        # get a list of known CONF_IF flags, spaces are not allowed
        conf_patched = {
            k: ""
            for k in re.findall(r"^#CONF_IF([_\S]+)", template, flags=re.MULTILINE)
        }
        conf_patched.update(conf)
        # sort keys first by length, then alphabetically to fix "_A_" and "_A_SFX_" case
        for expr, subst in sorted(
            conf_patched.items(), key=lambda p: (-len(p[0]), p[0])
        ):
            template = template.replace(expr, subst)
        # process "#CONF_IF" entries
        # spaces only are ignored
        template = re.sub(r"^#CONF_IF +\t", "#CONF_IF\t", template, flags=re.MULTILINE)
        # spaces followed by something are ok
        template = re.sub(r"^#CONF_IF[^\t]+\t", "#CONF\t", template, flags=re.MULTILINE)
        template = re.sub(r"^#CONF_IF\t", "#no CONF\t", template, flags=re.MULTILINE)
        outfile.write(template)
    return


def main():
    args = get_args()
    template = "".join(args.template.readlines())

    os.makedirs(args.output_dir, exist_ok=True)
    for conf in load_species_data(args.param_table, args.keep_empty_values):
        fill_template(template, conf, "_ABBREV_", args.output_dir, args.out_file_pfx)


# main
if __name__ == "__main__":
    # execute only if beeing run as a script
    main()
