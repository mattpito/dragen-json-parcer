#!/usr/bin/env bash
#
# nirvana_cnv_to_csv.sh
#
# Usage:
#   ./nirvana_cnv_to_csv.sh <GENE_LIST> <FILE_LIST> <OUTPUT_CSV>
#
# Where:
#   <GENE_LIST>  is a comma-separated list of gene symbols, e.g. 'GUSB,EGFR'
#   <FILE_LIST>  is a comma-separated list of files or a wildcard pattern in quotes, e.g. '*.cnv.annotations.json.gz'
#   <OUTPUT_CSV> is the CSV filename to write
#
# Examples:
#   1) Multiple genes, wildcard for files:
#       ./nirvana_cnv_to_csv.sh GUSB,EGFR "*.cnv.annotations.json.gz" all_samples.csv
#
#   2) Multiple genes, comma-separated file list:
#       ./nirvana_cnv_to_csv.sh GUSB,EGFR \
#           "LP2105628-DNA_A01_LP2105633-DNA_A01.cnv.annotations.json.gz,LP2105629-DNA_A01_LP2105633-DNA_A01.cnv.annotations.json.gz" \
#           genes_CNA.csv
#
#   3) Single gene, single file:
#       ./nirvana_cnv_to_csv.sh GUSB "LP2105628-DNA_A01_LP2105633-DNA_A01.cnv.annotations.json.gz" single_sample.csv
#

###############################################################################
### 1) Parse arguments
###############################################################################
if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <GENE_LIST> <FILE_LIST> <OUTPUT_CSV>"
  echo "  <GENE_LIST>   e.g. 'GUSB,EGFR'"
  echo "  <FILE_LIST>   e.g. '*.cnv.annotations.json.gz' (quoted) or 'fileA,fileB'"
  echo "  <OUTPUT_CSV>  output CSV filename"
  exit 1
fi

GENE_LIST="$1"     # e.g. "GUSB,EGFR"
FILE_LIST="$2"     # e.g. "*.cnv.annotations.json.gz" or "file1,file2"
OUTPUT_CSV="$3"

###############################################################################
### 2) Split the comma-separated gene list into an array
###############################################################################
IFS=',' read -ra GENE_ARRAY <<< "$GENE_LIST"

###############################################################################
### 3) Expand the file list
###    - Split by comma
###    - For each chunk, do 'eval echo' to expand wildcards
###############################################################################
IFS=',' read -ra CHUNKS <<< "$FILE_LIST"

FILES=()
for CHUNK in "${CHUNKS[@]}"; do
  # Evaluate CHUNK in case it contains a wildcard
  EXPANDED=( $(eval echo "$CHUNK") )
  
  if [[ -z "${EXPANDED[*]}" ]]; then
    # No matches => keep literal
    FILES+=("$CHUNK")
  else
    FILES+=("${EXPANDED[@]}")
  fi
done

###############################################################################
### 4) Create or overwrite the output CSV with a header
###############################################################################
echo "sample,gene,chromosome,start,end,filters,copyNumber,transcripts" > "$OUTPUT_CSV"

###############################################################################
### 5) Process each file & gene
###############################################################################
for FILENAME in "${FILES[@]}"; do
  # Check file existence
  if [[ ! -e "$FILENAME" ]]; then
    echo "Warning: '$FILENAME' not found. Skipping." >&2
    continue
  fi

  # Extract the second LP ID using grep + sed
  # Example: LP2105628-DNA_A01_LP2105633-DNA_A01.cnv.annotations.json.gz
  # -> grep finds LP2105628 and LP2105633
  # -> sed -n 2p prints the second occurrence => LP2105633
  SAMPLE=$(
    basename "$FILENAME" .cnv.annotations.json.gz \
    | grep -o 'LP[0-9]\+' \
    | sed -n 2p
  )

  # Loop over each gene in the list
  for GENE in "${GENE_ARRAY[@]}"; do
    zcat "$FILENAME" \
      | jq -r --arg SAMPLE "$SAMPLE" --arg GENE "$GENE" '
          .positions[]
          | {
              chromosome: .chromosome,
              start:      .position,
              end:        .svEnd,
              filters:    .filters,
              copyNumber: ( .samples[]?.copyNumber ),
              transcripts: (
                [ 
                  .variants[]?.transcripts[]?
                  | select(.hgnc == $GENE)
                  | .transcript
                ]
                | unique
              )
            }
          # Keep only if transcripts array is not empty
          | select(.transcripts | length > 0)

          # Output as CSV
          | [
              $SAMPLE,
              $GENE,
              .chromosome,
              .start,
              .end,
              (.filters | join(";")),
              .copyNumber,
              (.transcripts | join(";"))
            ]
          | @csv
        ' >> "$OUTPUT_CSV"
  done
done

echo "Done. Results are in: $OUTPUT_CSV"
