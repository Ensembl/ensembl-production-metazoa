[
  .taxon_id,
  .scientific_name,
  ._COMMON_NAME_,
  ._ABBREV_,
  ._GENOME_ACCESSION_,
  ._GENOME_FTP_URL_,
  ._REFSEQ_ANN_REPORT_URL_,
  ._REFSEQ_ANN_NAME_,
  ._ASSEMBLY_PROVIDER_NAME_,
  ._ANNOTATION_PROVIDER_NAME_
] | join("\t")
