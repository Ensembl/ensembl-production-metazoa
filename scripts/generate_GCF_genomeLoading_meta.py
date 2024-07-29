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
"""Obtain a set of RefSeq GCF accession(s) annotation meta information then store key information to
genome loading meta config file."""

__all__ = [
    "check_ncbi_url",
    "download_taxonomy",
    "dump_loading_metadata_to_tsv",
    "get_genome_loading_metadata",
]

import csv
import re
import logging
import sys
import tempfile
from typing import Dict
from pathlib import Path
from os import PathLike
from collections import Counter

import requests
from spython.main import Client
from sqlalchemy.engine import URL

from ensembl.io.genomio.assembly.status import singularity_image_setter
from ensembl.io.genomio.assembly.status import datasets_asm_reports
from ensembl.io.genomio.assembly.status import UnsupportedFormatError
from ensembl.io.genomio.database.dbconnection_lite import DBConnectionLite as dbc
from ensembl.io.genomio.utils.json_utils import get_json
from ensembl.io.genomio.utils.json_utils import get_json
from ensembl.utils.archive import extract_file
from ensembl.utils.logging import init_logging_with_args
from ensembl.utils.argparse import ArgumentParser


class LoadingMetaData(dict):
    """Dict setter class of key report meta information"""

    def __init__(self):
        dict.__init__(self)
        self.update(
            {
                "_COMMON_NAME_": "",
                "_SCIENTIFIC_NAME_NOT_USED_": "",
                "_TAXON_GROUP_": "",
                "_ABBREV_": "",
                "_GENBANK_ACCESSION_": "",
                "_REFSEQ_FTP_URL_": "",
                "_REFSEQ_ANN_REPORT_URL_": "",
                "_REFSEQ_ANN_NAME_": "",
                "_ASSEMBLY_PROVIDER_NAME_": "",
                "_ASSEMBLY_PROVIDER_URL_": "",
            }
        )


def check_ncbi_url(url: str) -> bool:
    """Checks the urls passed are live and link to active sites.

    Args:
        url: URL to be checked via requests.get

    Returns:
        True or False if URL is active and live.
    """

    try:
        url_get = requests.get(url)
        if url_get.status_code == 200:
            return True
        else:
            return False
    except requests.exceptions.RequestException as error:
        raise SystemExit(f"{url}: is Not reachable \nErr: {error}")


def get_genome_loading_metadata(
    assembly_reports: Dict[str, dict], datasets_image: Client
) -> Dict[str, LoadingMetaData]:
    """Parse the set of input assembly reports for loading meta info.

    Args:
        assembly_reports: Individual assembly reports JSONl one per accession
        datasets_image: datasets cli sif image

    Returns:
        Key assembly loading meta fields parsed from input assembly reports
    """
    parsed_meta = {}
    unique_abbrev = set()
    all_abbrevs = []

    for query_accession, asm_report in assembly_reports.items():

        logging.info(
            f"Obtaining genome loading metadata on accession: {query_accession}"
        )

        asm_meta_info = LoadingMetaData()
        assembly_provider_base_url = "https://www.ncbi.nlm.nih.gov/datasets/genome/"

        scientific_name = asm_report["organism"]["organism_name"]
        asm_meta_info["_SCIENTIFIC_NAME_NOT_USED_"] = scientific_name

        # Species abbreviation meta:
        abbrev_split = scientific_name.lower().split(" ")
        abbrev = f"{abbrev_split[0][0]}{abbrev_split[1][0:3]}"
        asm_meta_info["_ABBREV_"] = abbrev
        unique_abbrev.add(abbrev)
        all_abbrevs.append(abbrev)

        # Assembly name and FTP URL:
        tmp_name = asm_report["assembly_info"]["assembly_name"]
        assembly_name = tmp_name.replace(" ", "_")
        accession = asm_report["accession"]
        asm_meta_info["_GENBANK_ACCESSION_"] = accession
        first_digits = "".join(accession[4:7])
        second_digits = "".join(accession[7:10])
        third_digits = "".join(accession[10:13])
        base_url = "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF"
        # Generate FTP url from accession:
        ftp_url = f"{base_url}/{first_digits}/{second_digits}/{third_digits}/{accession}_{assembly_name}"
        if check_ncbi_url(ftp_url):
            asm_meta_info["_REFSEQ_FTP_URL_"] = ftp_url
        else:
            logging.warning(
                f'WARNING: RefSeq FTP URL "{ftp_url}" test connection failed.'
            )

        # Annotation meta:
        annotation_provider_url = asm_report["annotation_info"]["report_url"]
        if check_ncbi_url(annotation_provider_url):
            asm_meta_info["_REFSEQ_ANN_REPORT_URL_"] = annotation_provider_url
        else:
            logging.warning(
                f'WARNING: Annotation provider URL "{annotation_provider_url}" test connection failed.'
            )

        raw_anno_name = asm_report["annotation_info"]["name"]
        asm_meta_info[
            "_REFSEQ_ANN_NAME_"
        ] = f"NCBI {scientific_name} Annotation Release {raw_anno_name}"

        # Assembly provider meta:
        assembly_provider_url = assembly_provider_base_url + accession + "/"
        if check_ncbi_url(assembly_provider_url):
            asm_meta_info["_ASSEMBLY_PROVIDER_URL_"] = assembly_provider_url
        else:
            logging.warning(
                f'Warning: Assembly provider URL "{assembly_provider_url}" test connection failed.'
            )
        assembly_provider = asm_report["assembly_info"]["biosample"]["owner"]["name"]

        if assembly_provider is None or assembly_provider == "None":
            logging.warning(
                f"Unable to parse assembly assembly_provider for {query_accession} undefined or set to 'None'"
            )
            asm_meta_info["_ASSEMBLY_PROVIDER_NAME_"] = ""
        else:
            asm_meta_info["_ASSEMBLY_PROVIDER_NAME_"] = assembly_provider

        ## Get taxonomy info using datasets
        taxon_id = int(asm_report["organism"]["tax_id"])
        order_classification, groupname = download_taxonomy(
            datasets_image, taxon_id, "order"
        )
        asm_meta_info["_TAXON_GROUP_"] = order_classification

        # Test for common name present in main assembly/annotation report JSON or use taxonomy meta dump
        organism_type_keys = asm_report["organism"].keys()
        if "infraspecific_names" in organism_type_keys:
            if "common_name" in organism_type_keys:
                common_name = asm_report["organism"]["common_name"]
                asm_meta_info["_COMMON_NAME_"] = common_name.capitalize()
            else:
                asm_meta_info["_COMMON_NAME_"] = groupname
        else:
            asm_meta_info["_COMMON_NAME_"] = groupname

        parsed_meta[query_accession] = asm_meta_info

    # Checks for uniqueness of assigned sp name abbreviations
    if len(unique_abbrev) != len(assembly_reports.keys()):
        print("Found species with non-unique abbreviations")
        counts = dict(Counter(all_abbrevs))
        duplicates = {key: value for key, value in counts.items() if value > 1}
        count_suffix = 1
        for accession, genome_load_meta in parsed_meta.items():
            abbrev_to_check = genome_load_meta["_ABBREV_"]
            if (
                abbrev_to_check in duplicates.keys()
                and count_suffix <= duplicates[abbrev_to_check]
            ):
                genome_load_meta["_ABBREV_"] = f"{abbrev_to_check}{count_suffix}"
                count_suffix += 1
                parsed_meta[accession] = genome_load_meta
            else:
                parsed_meta[accession] = genome_load_meta
                count_suffix = 1

    return parsed_meta


def dump_loading_metadata_to_tsv(
    parsed_asm_reports: dict, outfile_prefix: str, output_directory: PathLike = Path()
) -> None:
    """Write all genome loading metadata to TSV file

    Args:
        parsed_asm_reports: Parsed assembly report meta
        outfile_prefix: Output file name prefix
        output_directory: Path to directory where output TSV is stored.
    """

    tsv_outfile = f"{output_directory}/{outfile_prefix}.tsv"

    with open(tsv_outfile, "w+") as tsv_out:
        writer = csv.writer(tsv_out, delimiter="\t", lineterminator="\n")
        writer.writerow(list(LoadingMetaData().keys()))

        for report_meta in parsed_asm_reports.values():
            final_asm_report = list(report_meta.values())
            writer.writerow(final_asm_report)
        tsv_out.close()


def download_taxonomy(sif_image: Client, taxon_id: int, taxon_level: str) -> str:
    """Obtain the corresponding linnaean information from a taxon ID using
    datasets cli to populate a species taxonomy meta info.

    Args:
        sif_image: Instance of Client.loaded singularity image.:
        taxon_id: Organismal taxon ID
        taxon_level: Taxonomy level requested for meta info

    Returns:
        Linnaean taxonomy meta info related to 'Order' and group name / common name

    """

    with tempfile.TemporaryDirectory() as tmp_dir_name:
        zip_archive = tmp_dir_name + "/" + str(taxon_id) + ".zip"
        unzipped_taxonomy = tmp_dir_name + "/ncbi_dataset/data/taxonomy_report.jsonl"

        # Make call to singularity datasets providing taxonomy ID as query:
        datasets_command = (
            ["datasets", "download", "taxonomy", "taxon"]
            + [str(taxon_id)]
            + ["--filename"]
            + [f"{zip_archive}"]
        )

        Client.execute(
            image=sif_image, command=datasets_command, return_result=True, quiet=True
        )

        extract_file(zip_archive, tmp_dir_name)
        taxonomy_json = get_json(unzipped_taxonomy)
        linnaean_order = taxonomy_json["taxonomy"]["classification"][taxon_level][
            "name"
        ]
        json_groupname = taxonomy_json["taxonomy"]["groupName"]

    return linnaean_order, json_groupname.capitalize()


def main() -> None:
    """Module's entry-point."""
    parser = ArgumentParser(description=__doc__)
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument(
        "--input_accessions",
        type=Path,
        required=False,
        default=None,
        help="List of assembly RefSeq 'GCF' query accessions",
    )
    parser.add_argument_dst_path(
        "--download_dir",
        default="Genome_metadata_jsons",
        help="Folder where the assembly report JSON file(s) are stored",
    )
    parser.add_argument_dst_path(
        "--outfile_metadata_prefix",
        default="_refseq",
        help="Prefix used in assembly report TSV output file.",
    )
    parser.add_argument(
        "--datasets_version_url",
        type=str,
        required=False,
        metavar="URL",
        help="datasets version",
    )
    parser.add_argument(
        "--cache_dir",
        type=Path,
        required=False,
        default="$NXF_SINGULARITY_CACHEDIR",
        metavar="SINGULARITY_CACHE",
        help="Custom path to user generated singularity container with NCBI's 'datasets' cli tool",
    )
    parser.add_argument(
        "--datasets_batch_size",
        type=int,
        required=False,
        default=20,
        metavar="BATCH_SIZE",
        help="Number of accessions requested in single query to datasets cli",
    )

    parser.add_log_arguments(add_log_file=True)
    args = parser.parse_args()

    init_logging_with_args(args)

    # Set and create dir for download files
    args.download_dir.mkdir(parents=True, exist_ok=True)

    ## Parse and store cores/accessions from user input query file
    with args.input_accessions.open(mode="r") as f:
        query_list = f.read().splitlines()

    query_accessions: Dict = {}
    for accession in query_list:
        match = re.match(r"(GCF)_([0-9]{3})([0-9]{3})([0-9]{3})\.?([0-9]+)", accession)
        if not match:
            raise UnsupportedFormatError(
                f"Could not recognize RefSeq accession format 'GCF_': {accession}"
            )
        query_accessions[accession] = accession

    ## Parse singularity setting and define the SIF image for 'datasets'
    datasets_image = singularity_image_setter(args.cache_dir, args.datasets_version_url)

    # Datasets query implementation for one or more batched accessions
    assembly_reports = datasets_asm_reports(
        datasets_image, query_accessions, args.download_dir, args.datasets_batch_size
    )

    # Parse assembly report JSON for meta info related to genome loading
    assembly_loading_meta_data = get_genome_loading_metadata(
        assembly_reports, datasets_image
    )

    dump_loading_metadata_to_tsv(
        assembly_loading_meta_data, args.outfile_metadata_prefix, args.download_dir
    )

    sys.exit(0)


if __name__ == "__main__":
    main()
