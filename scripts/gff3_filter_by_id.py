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

import sys

from ensembl.utils.argparse import ArgumentParser

def filter_out(dump_only: frozenset, check_keys: frozenset, ids: frozenset) -> None:
    # several use cases:
    # no ids to filter, dump key:         --dump_only "ID"
    # ids to filter for, dump key:        --dump_only "ID" --check_keys "ID,Parent" --ids_file combined.ids
    # ids to filter for, dump everythig:  --check_keys "ID,Parent" --ids_file seed.ids

    for line in sys.stdin:
        if line.startswith('#'):
            continue

        parts = line.rstrip().split("\t")
        fields = { k:v for k,v in map(lambda s: s.split("="), parts[8].split(";")) }

        # filter fields
        if check_keys:
            if not ids:
                continue
            # N.B. there could be several values joined with ','
            check_vals = ",".join([ v for k,v in fields.items() if k in check_keys ]).split(",")
            if not frozenset(check_vals) & ids:
                continue
            
        if dump_only:
            # N.B. there could be several values joined with ','
            out_vals = ",".join([ v for k,v in fields.items() if k in dump_only ]).split(",")
            print("\n".join(out_vals))
        else:
            sys.stdout.write(line)


def load_ids(file) -> frozenset:
    ids = frozenset()
    if file:
        with file.open() as f:
            ids = frozenset(filter(None, map(lambda s: s.rstrip(), f)))
    return ids

def get_args() -> None:
    parser = ArgumentParser()
    # various configs and maps
    parser.add_argument("--dump_only",
                        metavar="ID",
                        default="",
                        required=False,
                        type=str,
                        help="A ',' joined list of fields to dump values for")
    parser.add_argument("--check_keys",
                        metavar="ID,Parent",
                        default="",
                        required=False,
                        type=str,
                        help="A ',' joined list of fields to check")
    parser.add_argument_src_path("--ids_file", metavar="ids_file.lst",
                        required=False,
                        type=str,
                        help="file with IDs list to filter for")
    args = parser.parse_args()
    return args

def main(*args, **kwargs):
    args = get_args()
    
    dump_only = frozenset(filter(None, args.dump_only.strip().split(",")))
    check_keys = frozenset(filter(None, args.check_keys.strip().split(",")))

    if (bool(check_keys) ^ bool(args.ids_file)):
        print("both '--check_keys' and '--ids_file' should be present or absent, exiting...", file=sys.stderr)
        sys.exit(1)

    ids = load_ids(args.ids_file)
    filter_out(dump_only, check_keys, ids)

# main
if __name__ == "__main__":
    # execute only if beeing run as a script
    main()
