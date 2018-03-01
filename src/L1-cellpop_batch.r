#!/usr/bin/env Rscript

#--- Load libraries and necessary data files, and define global variables
######################################################################################
library(data.tree)
library(data.table)
library(Biostrings)
library(BSgenome.Hsapiens.UCSC.hg38)
library(GenomicRanges)
genome <- Hsapiens
source("process_L1s.r")
source("mapsequence.r")
load("../data/chrmpd.rda") # load chromosome probability distribution
load("../data/L1RankTable.rda")
load("../data/exann.rda")
trpd <- read.table("../data/L1truncpd.csv",sep=",")
tdpd <- read.table("../data/L1transdpd.csv",sep=",")
for (i in names(Hsapiens)[1:24]){ # load all chromosome map files
	cat(paste0("Loading map file...",i,"\n"))
    load(paste0("../data/root_maps/",i,".rda"))
}
strdict<-c("+","-")
names(strdict)<-c(1,2)


#--- Define functions
######################################################################################

# PURPOSE: To simulate the transposition of an L1 sequence in a given genome
#
# INPUT:
#   genome        (BSgenome) reference genome
#   node          (data.tree node) input node of tree
#   copyNum       (integer) number of L1 insertions to simulate
#
# OUTPUT: (list) inserted sequences, sites, and strand
gen_sim <- function(genome,node,copyNum) {

        sites_loci<-c() # Initialize arrays for storing simulated ins. site data
        sites_chrm<-c()
        sites_strand<-c()
        sites_classes<-c()

        #--- Sample chromosomes based on probability ranking. The data file chrmpd.rda 
        #--- must either be provided or generated by running 'get_sv_dist.r'.
        #--- Here the ranking is provided by the number of 'TTTT' (closed-tight) sites.
        chrmlist<-sample(x=names(genome)[1:24],copyNum,replace=TRUE,prob=chrmcnt[,1])
        chrmlist<-table(chrmlist)

        for (chrnm in names(chrmlist)) {


#                 cat("\nChromosome: ",chrnm)

                map<-get(paste0(chrnm,"Map"))
                map<-update_chrom_map(chrnm,map,node$tes[[2]],node$tes[[3]],node$tes[[1]])
                ict<-map[[2]]
                icl<-map[[3]]
                iot<-map[[4]]
                iol<-map[[5]]
                insites<-map[[1]]


                chrcopyNum<-chrmlist[[chrnm]]

                pd <- c(11.55*length(which(!is.na(ict))),
                        7.25*length(which(!is.na(icl))),
                        1.95*length(which(!is.na(iot))),
                        1*length(which(!is.na(iol))))
                pd <- (pd/sum(pd))*(1-ENifrc)
                pd <- append(pd,ENifrc)
#                 cat("\nSite class distribution:\n",pd)

                #--- Generates insertion sites
                classes <- sample(x = c(1:5),chrcopyNum,replace=TRUE,prob=pd)
                sites <- rep(0,chrcopyNum)
                strand <-rep(0,chrcopyNum)

            
                for (i in 1:chrcopyNum) {
                        if (classes[i]==1) {
                            tmp<-sample(c(1,2),1)
                            sites[i] <- insites[ict[sample(c(1:length(which(!is.na(ict[,tmp])))),1),tmp]]
                            strand[i] <- strdict[[tmp]]
                        } else if (classes[i]==2) {
                            tmp<-sample(c(1,2),1)
                            sites[i] <- insites[icl[sample(c(1:length(which(!is.na(icl[,tmp])))),1),tmp]]
                            strand[i] <- strdict[[tmp]]
                        } else if (classes[i]==3) {
                            tmp<-sample(c(1,2),1)
                            sites[i] <- insites[iot[sample(c(1:length(which(!is.na(iot[,tmp])))),1),tmp]]
                            strand[i] <- strdict[[tmp]]
                        } else if (classes[i]==4) {
                            tmp<-sample(c(1,2),1)
                            sites[i] <- insites[iol[sample(c(1:length(which(!is.na(iol[,tmp])))),1),tmp]]
                            strand[i] <- strdict[[tmp]]
                        } else if (classes[i]==5) {
                            sites[i]<-runif(1,1,length(genome[[chrnm]]))
                            strand[i] <- strdict[[sample(c(1,2),1)]]
                        }
                }

                sites_loci<-append(sites_loci,sites)
                sites_chrm<-append(sites_chrm,rep(chrnm,chrcopyNum))
                sites_strand<-append(sites_strand,strand)
                sites_classes<-append(sites_classes,classes)

        }

        #--- Creates sequences for insertion
        tmp <- process_L1s(genome,L1RankTable,trpd,tdpd,copyNum)
        l1s <- tmp[[1]]
        l1indcs <- tmp[[2]]
        tdlen <- tmp[[3]]
        trlen <- tmp[[4]]
        return(list(l1s,sites_chrm,sites_loci,sites_strand))
}


# PURPOSE: To check whether the division rate of a new clone should be changed from its parent
#
# INPUT:
#   r             (float) division rate
#   geneann       (data frame) Annotation of genes (i.e. chromosome   start   end)
#   sites_chrm    (numeric vector) chromosomes containing L1 insertions for the clone
#   sites_loci    (character vector) insertion positions (in the respective chromosome)
#
# OUTPUT: (float) possibly updated division rate
rank_clone <- function(r, geneann, sites_chrm, sites_loci, gainp, lossp) {

    gene_hits=0; # set counter to zero
    tsg_hits=0;
    for (i in 1:length(unique(sites_chrm))) { # loop over chromosomes inserted into
        tmp=geneann[geneann$chrom==unique(sites_chrm)[i],] # reduce annotation table to entries for current chrom
        chrmann_ntsg=tmp[tmp$istsg==0,]
        chrmann_tsg =tmp[tmp$istsg==1,]
        tmp = sites_loci[sites_chrm==unique(sites_chrm)[i]] # reduce insertion loci to entries for current chrom
        tmp_hits = between(tmp,chrmann_ntsg$start,chrmann_ntsg$end) # create logical for insertions, whether into non-tsg-gene or not
        gene_hits=gene_hits+length(which(tmp_hits==TRUE)) # count the number of non-tsg-gene insertions
#         print(gene_hits)
        tmp_hits  = between(tmp,chrmann_tsg$start,chrmann_tsg$end) # same for tsg-gene insertions
        tsg_hits =tsg_hits+length(which(tmp_hits==TRUE))
    }

    if (gene_hits > 0) {
        r=r*lossp^gene_hits
    } else if (tsg_hits > 0) {
        r = r*gainp^tsg_hits
    }

    if (r < 0.25) { # If the division rate is below 0.25, the clone stops growing
        r<-0
    }

    return(r)
}

# PURPOSE: To update the insertion site annotation of a chromosome for a clone.
# The L1 insertions which have occurred in the clone will be accounted for
#
# INPUT:
#   chrnm         (string) chromosome name
#   chrMap        (list) chromosome annotation
#   sites_chrm    (numeric vector) chromosomes containing L1 insertions for the clone
#   sites_loci    (character vector) insertion positions (in the respective chromosome)
#   l1s           (DNAStringSet) l1 sequences and orientation 
#
# OUTPUT: (list) updated chromosome annotation
update_chrom_map <- function(chrnm,chrMap,sites_chrm,sites_loci,l1s) {

        if (length(which(sites_chrm==chrnm))==0){
                return(chrMap)
        }

        ict<-chrMap[[2]]
        icl<-chrMap[[3]]
        iot<-chrMap[[4]]
        iol<-chrMap[[5]]
        insites<-chrMap[[1]]

        chrloci = sites_loci[sites_chrm==chrnm] # Get the sites where insertions occurred in the chromosome
        chrl1s = l1s[sites_chrm==chrnm] # Get the L1s elements which were inserted    
    
        for (i in 1:length(chrloci)) { # Loop over the simulated insertion sites
                insites[which(is.na(insites))]<- -1 # Replace NA with -1
                indx <- insites>chrloci[i] # Get indices of target sites which lie downstream of the site
                insites[indx] <- insites[indx] + width(chrl1s[i]) # Shift the target sites by the length of the L1
                l1_map <- mapsequence(chrl1s[i]) # Map target sites in the L1
                l1_map$insites <- l1_map$insites + chrloci[i] # Convert L1 loci to chromosome loci
                insites <- rbind(insites,l1_map$insites) # Add target sites within L1 to chrom map
                ict <- rbind(ict,l1_map$ict)
                icl <- rbind(icl,l1_map$icl)
                iot <- rbind(iot,l1_map$iot)
                iol <- rbind(iol,l1_map$iol)
        }

        return(list(insites,ict,icl,iot,iol))

}

# PURPOSE: Updates the gene annotation of the clone
#
# INPUT:
#   geneann         (data frame) Annotation of genes (i.e. chromosome   start   end)
#   simout          (list of lists) gen_sim output
#   tes             (list of lists) Node tes
#
# OUTPUT: geneann
update_geneann <- function(geneann, simout, tes) {
    
    tmp = mapply(append, simout, tes, SIMPLIFY = FALSE)
    for (i in 1:length(tmp[[3]])) {
        # Shift the start loci of genes with start loci beyond the insertion by the width of the L1
        geneann[geneann$chrom==tmp[[2]][i] & geneann$start>tmp[[3]][i],]$start <- geneann[geneann$chrom==tmp[[2]][i] & geneann$start>tmp[[3]][i],]$start + width(tmp[[1]][i])  
        # Shift the end loci of genes with start loci beyond the insertion by the width of the L1
        geneann[geneann$chrom==tmp[[2]][i] & geneann$start>tmp[[3]][i],]$end <- geneann[geneann$chrom==tmp[[2]][i] & geneann$start>tmp[[3]][i],]$end + width(tmp[[1]][i])  
        # Shift the end locus of any gene with only end locus beyond the insertion by the width of the L1
        geneann[geneann$chrom==tmp[[2]][i] & geneann$end>tmp[[3]][i] & geneann$start<tmp[[3]][i],]$end <- geneann[geneann$chrom==tmp[[2]][i] & geneann$end>tmp[[3]][i] & geneann$start<tmp[[3]][i],]$end + width(tmp[[1]][i])        
    }
    return(geneann) 
}


# PURPOSE: To call gen_sim.r with some probability (probability of transposition, tp) for a clone at a time step
#
# INPUT:
#   node          (data.tree node) current node of the data tree
#   tnum          (integer) time step number
#
# OUTPUT: void
# maybeTranspose <- function(node,tnum) {
    
#     if (node$r==0){ # If the division rate of the clone is zero, skip the node
#         return()
#     }
    
#     nc <- node$ncells[length(node$ncells)] + round(node$ncells[length(node$ncells)]*node$r)
#     # Sample from binomial distribution for number of transpositions
#     if (node$ncells[length(node$ncells)] < 4.2e9) {ntrans <- rbinom(1,node$ncells, cellP)} # rbinom() fails for large n
#     else {ntrans <- node$ncells*cellP} # If n is too large, use the expected number of events (mean of distribution)
#     if (ntrans > 0) {
#         simout <- gen_sim(genome,node,ntrans)
#         nc <- nc-ntrans
#         for (i in 1:ntrans) {
#             tmp <- update_geneann(exann,lapply(simout,'[',i),node$tes)
#             r_tmp <- rank_clone(node$r, tmp, lapply(simout,'[',i)[[2]], lapply(simout,'[',i)[[3]],1.2,0.8)
#             tmp<-mapply(append, lapply(simout,'[',i), node$tes, SIMPLIFY = FALSE)
#             node$AddChild(tnum, ncells=1, r=r_tmp, tes=tmp)
#         }
#     }
#     node$ncells <- append(node$ncells,nc)
    
# }


#--- Set simulation parameters
######################################################################################

ENifrc<- .1       # Fraction of endonuclease-independent (random) insertions
rootNCells <- 1   # Initial number of cells in root clone
rootDivRate <- 1  # Initial division rate
cellP <- 0.05     # Probability of transposition / timestep of a single cell

NT <- 15          # Number of time steps

#--- Generate clone tree
######################################################################################

gainp = c(rep(1.1,3),rep(1.2,3),rep(1.3,3),rep(1.4,3),rep(1.5,3),rep(1.6,3),rep(1.7,3),rep(1.8,3))
lossp = c(rep(.9,3),rep(.8,3),rep(.7,3),rep(.6,3),rep(.5,3),rep(.4,3),rep(.3,3),rep(.2,3))

for (nrun in 1:24) {

    CellPop <- Node$new(1)
    CellPop$ncells <- c(rootNCells)
    CellPop$r <- rootDivRate
    # CellPop$tes <- list(DNAStringSet(c("TCGA")),c("chr1"),c(1013467),c("+"))
    CellPop$tes <- list(DNAStringSet(),c(),c(),c())
    # CellPop$r <- rank_clone(CellPop$r, exann, CellPop$tes[[2]], CellPop$tes[[3]], 1.2, 0.8)
    # CellPop$r

    maybeTranspose <- function(node,tnum) {

        if (node$r==0){ # If the division rate of the clone is zero, skip the node
            return()
        }

        nc <- node$ncells[length(node$ncells)] + round(node$ncells[length(node$ncells)]*node$r)
        # Sample from binomial distribution for number of transpositions
        if (node$ncells[length(node$ncells)] < 4.2e9) {ntrans <- rbinom(1,node$ncells, cellP)} # rbinom() fails for large n
        else {ntrans <- node$ncells*cellP} # If n is too large, use the expected number of events (mean of distribution)
        if (ntrans > 0) {
            simout <- gen_sim(genome,node,ntrans)
            nc <- nc-ntrans
            for (i in 1:ntrans) {
                tmp <- update_geneann(exann,lapply(simout,'[',i),node$tes)
                r_tmp <- rank_clone(node$r, tmp, lapply(simout,'[',i)[[2]], lapply(simout,'[',i)[[3]],1.2,0.8)
                tmp<-mapply(append, lapply(simout,'[',i), node$tes, SIMPLIFY = FALSE)
                node$AddChild(tnum, ncells=1, r=r_tmp, tes=tmp)
            }
        }
        node$ncells <- append(node$ncells,nc)

    }

    ptm <- proc.time()
    for (i in 2:NT) {

            CellPop$Do(maybeTranspose,i)

    }
    print(proc.time() - ptm)

    save("CellPop",file=paste0("../../Data/SimOut4/",nrun,".rda"))
    rm(CellPop)

}




