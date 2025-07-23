# adding ftp and assembly_report urls
import json
from collections import defaultdict
import re
import sys

reports_data = defaultdict(dict)
for line in sys.stdin:
    acc, tag, value = map(lambda s: s.strip(" :#") , line.rstrip().split(":", 2))
    reports_data[acc].update({tag : value})

jsonl_file = sys.argv[1]
for line in open(jsonl_file):
    data = json.loads(line.rstrip())
    acc = data["_GENOME_ACCESSION_"]
    submitter = reports_data.get(acc, {}).get("Submitter", "")
    org_name = reports_data.get(acc, {}).get("Organism name", "")
    common_name = ""
    m = re.search(r'\(([^()]+?)\)$', org_name)
    if m:
      common_name = m.group(1).capitalize()
    data.update(
        _ASSEMBLY_PROVIDER_NAME_ = submitter,
        _COMMON_NAME_ = common_name,
    )
    # update annotation name and provider for those from GenBank
    anno_name = data.get("_REFSEQ_ANN_NAME_")
    if not anno_name or anno_name.startswith("Annotation submitted by"):
        data.update(
            _REFSEQ_ANN_NAME_ = "",
            _ANNOTATION_PROVIDER_NAME_ = data.get("_ASSEMBLY_PROVIDER_NAME_", "")
        )
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
        _ABBREV_ = abbr1[:1] + abbr2[:5]
    )
    #
    print(json.dumps(data))
