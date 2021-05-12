# Metaconf deprecated options


## Loading

### Pre-initialise
```
DATA_INIT	cp /.../old/assemblies/canu/canu4_A_ref.fa data.pre/aatro
DATA_INIT	gzip -r data.pre/aatro
DATA_INIT	mkdir -p data.pre/aatro
```
```
INIT_CMD	cp /.../canu4_assembly/canu4_A_alt.fa.gz data.pre/aatro_alt
INIT_CMD	gzip -r data.pre/aatro_alt
INIT_CMD	mkdir -p data.pre/aatro_alt
```
### Source data
`RNA_FILE`

### Many level assemblies
```
LOWER_CS_RANK	4
SPLIT_INTO_CONTIGS	1
KEEP_CTG_SCF_CHR_MAPPING	0
```
```
ALT_MAPPING_CMD	'cat GCA_002892825.2_ISE6_asm2.2_deduplicated_assembly_structure/all_alt_scaffold_placement.txt | cut -f 4,7,9,10-12,13-14 | grep -v na'
ASM_SCAF_MAPPING_FILE	GCA_004352715.1_Hmi_1.0_assembly_report.txt
```
```
HAS_NON_REF	1
HAS_NON_REF_MAPPING	1
```
```
NON_REF_IDS_CMD	cat GCA_002892825.2_ISE6_asm2.2_deduplicated_assembly_structure/Alts/component_localID2acc | tail -n +2 | cut -f 2
NON_REF_IDS_CMD	cat GCA_004136515.2_ASM413651v2_assembly_structure/haplotigs/component_localID2acc | tail -n +2 | cut -f 2
NON_REF_IDS_CMD	zcat GCA_003951495.1_AfunF3_assembly_structure/*/unplaced_scaffolds/AGP/unplaced.scaf.agp.gz | grep ^RCWQ | cut -f 1 | sort  | uniq
```
```
OLD_REGION_SYNS_CMD
OLD_REGION_SYNS_DB	drosophila_melanogaster_core_98_7
```

### Models import / GFF related
```
GFF_LOGIC_NAME
GFF_GENE_SOURCE	Ensembl_Metazoa
```
```
PREPROCESS_GFF	YES
```
```
DROP_CD_PFX	cds-
DROP_EXON_PFX	exon-gnl|WGS:VCGU|
DROP_GENE_PFX	gene-
DROP_MRNA_PFX	rna-gnl|WGS:VCGU|
```
```
ORIG_GENE_PFX	AATE
ORIG_GENE_PFX	g
ORIG_GENE_PFX	gene
```
```
APPLY_PROTEIN_SEQEDITS	YES
```

### Various
```
TAXON_ID	7227
```
```
COPY_STABLE_IDS_HISTORY	YES
```

## ATAC (lastz)
```
ATAC_FROM_CMD
ATAC_FROM_DB	anopheles_atroparvus_core_1906_95_3
ATAC_FROM_DB_GENES	anopheles_gambiae_core_1904_95_4
```

## PROJECTIONS
```
PROJ_COMPARA_CMD
PROJ_COMPARA_DB	ensembl_compara_master
PROJ_COMPARA_FILTER_SRC	YES
PROJ_COMPARA_FROM_CMD
PROJ_COMPARA_FROM_DB	anopheles_atroparvus_core_1906_95_3
PROJ_COMPARA_FROM_GENEPFX	AATE
```
```
COMPARA_PROJ_TO_GFF_OPTS	-exon_inflation_max 3 -exons_gained_max 10
COMPARA_PROJ_TO_GFF_OPTS	-exon_inflation_max 3 -unplaced_ctg "UNK" -exons_gained_max 10
```

## PIPELINES
```
RUN_VB_XREF	NO/YES
```
```
REPBASE_SPECIES_NAME	Drosophila_melanogaster
RM_CLEAN_PEP_FILE	/.../Anopheles-funestus-FUMOZ_PEPTIDES_AfunF1.10.fa.gz
RM_CLEAN_RNA_FILE	/.../Ixodes-scapularis-Wikel_TRANSCRIPTS_IscaW1.6.fa.gz
```
