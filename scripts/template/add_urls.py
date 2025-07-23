# adding ftp and assembly_report urls
import json
import re
import sys

url_pfx = sys.argv[1].rstrip(" /")

def get_ftp_url_and_asm_report(data, url_pfx):
    acc = data["_GENOME_ACCESSION_"]
    asm_name = data["assembly_name"].replace(" ","_")

    match = re.search(r'^(GC[AF])_(\d{3})(\d{3})(\d{3})\.\d+', acc)
    middle_bit = "/".join(match.groups())
    ftp_url = f"{url_pfx}/{middle_bit}/{acc}_{asm_name}"
    asm_report = f"{ftp_url}/{acc}_{asm_name}_assembly_report.txt"

    return { "_GENOME_FTP_URL_" : ftp_url, "assembly_report_url": asm_report }

for line in sys.stdin:
    data = json.loads(line.rstrip())
    data.update(get_ftp_url_and_asm_report(data, url_pfx))
    print(json.dumps(data))
