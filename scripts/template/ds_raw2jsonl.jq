.reports.[] | {
  _GENOME_ACCESSION_: .accession,
  current_accession: .current_accession,
  paired_accession: .paired_accession,
  assembly_name: .assembly_info.assembly_name,

  _REFSEQ_ANN_NAME_: .annotation_info.name,
  _REFSEQ_ANN_REPORT_URL_: .annotation_info.report_url,
  _ANNOTATION_PROVIDER_NAME_: .annotation_info.provider,

  taxon_id: .organism.tax_id,
  scientific_name: .organism.organism_name,
}
