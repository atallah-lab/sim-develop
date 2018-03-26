# sim-develop
An R project developed to simulate transposable element activity in genome evolution.
### Background 
---
#### Introduction
 As reported by Monot (Monot, C. et al. 2013) L1 retrotransposons utilize an endonuclease (EN) to initiate retrotransposition by first nicking the genomic DNA. The DNA end that results is then used to prime transcription within the L1 RNA poly(A) tail. This process is known as __target-primed reverse transcription (TPRT)__. Efficient priming is detected with only 4 matching nucleotides at the primer's 3' end. Furthermore, the L1 ribonucleoprotein particle (RNP) tolerates terminal mismatches if they are compensated for within the final 10 bases of the primer by an increase in the number of matching nucleotides.

#### What's the 'Snap-Velcro' Model?
Prior studies have demonstrated that most L1 insertions occur in sequences related to the L1 EN consensus sequence (degenerate 5′-TTTT/A- 3′ sites). The *Snap-Velcro* model describes four possible insertion sites that are modeled by two key parameters. The *snap* parameter represents the last four nucleotides of the primer. It is considered to be a perfect terminal match and 'closed' if it ends with four T’s. Alternatively, the snap is 'open' if it contains a mismatch in the last four T’s. The *velcro* region of the primer (6 upstream basepairs) is classified as either *tightly-fastened* or *loosely-fastened* based on its position-weighted T-density score (Monot et al., 2013). Thus, the distribution of new L1 insertions within the human genome is the result, in part, of the specificity of the initial EN cleavage site of L1 reverse transcription initiation.

#### What's a position weighted T-density score?
A T-density is calculated by dividing the number of Ts in the oligonucleotide by the length of the oligonucleotide. The position-weighted T-density gives more weight to Ts which are closer to the 3' end of the primer. The weight is inversely proportional to the distance from the 3' end.

LOU519:
GAGCCAGGAGGAATACTTTT
1 + (1/2) + (1/3) + (1/4) + (1/7) = **2.23**

LOU541:
TTTTTTTTTTTTTTTTTTTT
1 + (1/2) + (1/3) + ... + (1/19) + (1/20) = **3.60**

The position-weighted T-density is calculated by dividing the position-weighted T-count of a primer to the maximum position-weighted T-count. Thus the position-weighted T-density of LOU519 is equal to 0.62 (2.23/3.60) and the position-weighted T-density of LOU541 is equal to 1 (3.60/3.60). 

The *maximum* velcro score corresponds to six consecutive T’s and is:

GAGCCAGCCATTTTTTTTTT
(1/5) + (1/6) + ... + (1/10) = **0.84563492** 

Each score for a velcro region is divided by this maximum score as a normalization. If the position-weighted T-density score of the velcro region is ≥0.5 then that region is considered tightly-fastened, otherwise it is loosely-fastened.

#### Relevance of 'Snap-Velcro' Model in the Simulation of Transposable Elements
Monot et al. studed the relative enrichment of L1 insertion frequencies amongst the four snap-velcro categories in humans. They recorded the number of insertions observed at each type of EN site and divided this by the number of site-types in the reference genome (hg19 in their study). Amongst two datasets of human L1 insertions (Solyom, 2012; Lee, 2012) they found that the average relative enrichment for the closed/tight, closed/loose, open/tight, and open/loose categories was, respectively 11.55, 7.25, 1.95, 1.00. 


## Source Code

#### L1-cellpop.r
* Script for simulating evolution of a cell population, incorporating L1 retrotransposition events and response to mutations
```
./L1-cellpop.r <mode> <number of timesteps> <output file name>
```
* number of timesteps: at each timestep, the number of cells is updated for each clone based on its division rate, and cells in the population may experience transpositions, creating new clones in the population.
* mode: 
    + 'single' - run the simulation once for a number of timesteps
    + 'batch' - run the simulation a number of times, each for a number of timesteps (the number of each run is appended to the provided output file name to save each run separately). Parameters are varied for each run as written in the script.
    + 'endless' - run the simulation until manually terminated, saving the results at each timestep
 
#### L1-cellpop-lite.r
* A simplified version of L1-cellpop.r in which insertions are always simulated using the reference genome

#### L1-cellpop.ipynb
* Notebook version of the L1-cellpop.r script, for development

#### gen-sim.r
* Script for simulating retrotransposition of L1 elements in a single genome
* Insertion site probabilities based on Snap-Velcro model (Monot et al., 2013)
* Truncation modeled after Lee et al. (2012)
* Transduction modeled after Goodier et al. (2000)
* Dependencies: R(>= 2.8.0, Packages - Biostrings, BSgenome (for default hg38), GenomicRanges)
* *Monot et al., 2013, The Specificity and Flexibility of L1 Reverse Transcription Priming at Imperfect T-Tracts*
* *Lee et al., 2012, Landscape of Somatic Retrotransposition in Human Cancers*
* *Goodier et al., 2000, Transduction of 3′-flanking sequences is common in L1 retrotransposition*
```
./gen-sim.r <copy number>
```

#### gen-sim-notebook.ipynb
* This is a highly commented, notebook version of the site-generation part of gen-sim.r meant for learning and
developing the genome-level retrotransposition model.
* Dependencies: R(>= 2.8.0, Packages - Biostrings, BSgenome (for default hg38), GenomicRanges), Jupyter, IRKernel


#### mapchrom_parallel.r
* Experiment in parallelization applied to mapchrom.r 
* Dependencies: R(>= 2.8.0, Packages - Biostrings, BSgenome (for default hg38), parallel, foreach, doParallel)
```
./mapchrom_parallel.r <chromosome start number (e.g. 1-23), <chromosome stop number (e.g. 2-24)>
```
#### mapgenome.r
* Maps potential L1 insertion sites based on the Snap-Velcro model (Monot et al.). Creates an .rda file for each chromosome in a provided range.
```
./mapgen.r <start chromosome # (e.g. 1)> <end chromosome # (e.g. 24)>
```
#### mapsequence.r
* Function to map potential L1 insertion sites within a provided DNAString object

#### get_sv_dist.r
* Stores the counts of each EN site category for each chromosome in a 24 x 4 matrix.

#### hgextract.r
* Extracts segments from a genome in ranges provided in a tab-delimited text file, and outputs the results to a Fasta file.

#### makeL1RankTable.r
* Creates a .rda file containing the loci of retrotransposition-competent L1's in hg38 and their rankings.

#### process_L1s.r
* Function to simulate truncation and transduction of L1 elements selected for retrotransposition based on activity ranking.

#### gcbasedins.r
* Insert L1 element copies in a given chromosome with probability based on local G/C content.
* Dependencies: R(>= 2.8.0, Packages - Biostrings, BSgenome (for default hg38))
```
./gcbasedins.r <optional: input genome (fasta, default - hg19)> <output file name (fasta)>
```

#### map_L1_consensus_sequences_hg38.R
* Map an arbitrary set of L1 consensus sequences against hg38. 

## Data

#### ./data/root_maps
* Make this file a soft link to a directory for storing the chromosome map files (~ 3GB) generated by mapgenome.r

#### ./data/GenBank_L19092.fa 
* consensus sequence retrieved from GenBank, https://www.ncbi.nlm.nih.gov/nuccore/L19092.1?report=GenBank

#### ./data/Brouha_consensus_L1.fa 
* Hot L1 consensus sequence taken from Brouha et al. paper. 

#### ./data/gb_AC002980.fa 
* Set of 5 L1 consensus sequences retrieved from NCBI BLAST search against hg38 for Accession No. AC002980. (07/17/2017). This was the top hit noted in Table 4 of the Brouha paper. 

#### ./data/hsflil1_8438.bed
* BED file retrieved from L1Base, http://l1base.charite.de/BED/hsflil1_8438.bed

#### ./data/L1PA
* directory to hold L1PA annotation output.

#### ./data/L1PA/by_chr
* all L1PA annotation output, by chromosome.

#### ./data/L1PA/L1PA.fa
* L1PA2, L1PA3, L1PA4 sequences.

#### ./data/L1PA/L1PA2.bed, L1PA3.bed, L1PA4.bed
* L1PA2|3|4 annotation output, by sequence, over entire genome.
