import argparse
import re
import os
import sys

from os.path import join as pj

def get_args():
  parser = argparse.ArgumentParser()
  # various configs and maps
  parser.add_argument("--template", metavar="refseq.tmpl", required=True,
                      type=argparse.FileType('rt', encoding='UTF-8'),
                      help="template file to use")
  parser.add_argument("--param_table", metavar="_species.lst", required=True,
                      type=argparse.FileType('rt', encoding='UTF-8'),
                      help="species data as a tsv file with header")
  parser.add_argument("--output_dir", metavar="_species.lst", required=False,
                      type=str, default='.', 
                      help="directory to write results to")
  parser.add_argument("--out_file_pfx", metavar="rs_", required=False,
                      type=str, default='', 
                      help="directory to write results to")
  args = parser.parse_args()
  return args

def load_species_data(infile):
  out = []
  header = None
  for line in infile:
    line = re.sub("#.*$", "", line)
    if not line.strip():
      continue
    if not header:
      header = list(map(lambda s: s.strip(), line.strip().split()))
      continue
    conf_raw = list(map(lambda s: s.strip(), line.strip().split("\t"))) + [""] * len(header)
    conf = dict(zip(header, conf_raw[:len(header)]))
    if "" in conf.values():
      print(f"# warning: ignoring incomplete configuration: {conf}" , file = sys.stderr)
      continue
    # print(f"configuration: {conf}" , file = sys.stderr)
    out.append(conf)
  return out
  
def fill_template(template : str, conf : dict, name_field : str, dir_path : str, file_pfx : str = ""):
  name = conf.get(name_field, name_field)
  filename = pj(dir_path, file_pfx + name)
  with open(filename, "w") as outfile:
    print(f"# creating '{name}' meta file", file = sys.stderr)
    template = str(template)
    for expr, subst in conf.items():
      template = template.replace(expr, subst)
    outfile.write(template)
  return

def main():
  args = get_args()
  template = "".join(args.template.readlines())

  os.makedirs(args.output_dir, exist_ok = True)
  for conf in load_species_data(args.param_table):
     fill_template(template, conf, "_ABBREV_", args.output_dir, args.out_file_pfx)

# main
if __name__ == "__main__":
  # execute only if beeing run as a script
  main()




