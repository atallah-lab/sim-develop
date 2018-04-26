#!/usr/bin/env Rscript

# Arguments:
#
# (1) - run type ('single', 'batch', 'endless', see below)
# (2) - number of timesteps
# (3) - output file name
# 
# 'single' runs the simulation once for the specified number of timesteps and saves the result
# 'batch' runs the simulation a number of times (see batch section) while varying parameters, and saves results separately
# 'endless' runs the simulation endlessly (until manual termination) and saves the results to the same file after each timestep 

#--- Load libraries and necessary data files, and define global variables
######################################################################################
library(data.tree)
library(data.table)
library(Biostrings)
library(BSgenome.Hsapiens.UCSC.hg38)
library(GenomicRanges)
genome <- Hsapiens
load("../data/exann.rda")
load("../data/chrmpd.rda") # load chromosome probability distribution
load("../data/L1RankTable.rda")
load('../data/chromSitePd.rda')
trpd <- read.table("../data/L1truncpd.csv",sep=",")
tdpd <- read.table("../data/L1transdpd.csv",sep=",")
for (i in names(Hsapiens)[1:24]){ # load all chromosome map files
        cat(paste0("Loading map file... ",i,"\n"))
        load(paste0("../data/root_maps/",i,".rda"))
}
strdict<-c("+","-")
names(strdict)<-c(1,2)

args<-commandArgs(trailingOnly=TRUE)

#--- Define functions
######################################################################################

# PURPOSE: To simulate the transposition of an L1 sequence in a given genome
#
# INPUT:
#   copyNum       (integer) number of L1 insertions to simulate
#
# OUTPUT: (list) inserted sequences, sites, and strand

gen_sim <- function(copyNum) {

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

                map<-get(paste0(chrnm,"Map"))
                ict<-map[[2]]
                icl<-map[[3]]
                iot<-map[[4]]
                iol<-map[[5]]
                insites<-map[[1]]

                chrcopyNum<-chrmlist[[chrnm]]

                #--- Generates insertion sites
                classes <- sample(x = c(1:5),chrcopyNum,replace=TRUE,prob=pds[[chrnm]])
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

        # Sample copyNum L1s from the list (with replacement), based on activity ranking
        l1indcs <- sample(x=c(1:40), copyNum, replace=TRUE, prob=L1RankTable$score[1:40])

        # Sample copyNum truncation fractions and transduction lengths from their respective 
        # probability densities trpd, and tdpd
#         trfrc <- sample(x=trpd[[1]], copyNum, replace=TRUE, prob=trpd[[2]])
#         tdlen <- sample(x=tdpd[[1]], copyNum, replace=TRUE, prob=tdpd[[2]])

    return(list(sites_chrm,sites_loci,sites_strand,l1indcs))
}


# PURPOSE: To check whether the division rate of a new clone should be changed from its parent
#
# INPUT:
#   r             (float) division rate
#   anno          (data frame) Annotation of genes (i.e. chromosome   start   end)
#   sites_chrm    (numeric vector) chromosomes containing L1 insertions for the clone
#   sites_loci    (character vector) insertion positions (in the respective chromosome)
#   gainp         (factor by which the division rate changes if a non-TSG is disrupted)
#   lossp         (factor by which the division rate changes if a TSG is disrupted)
#
# OUTPUT: (float) possibly updated division rate
rank_clone <- function(r, anno, sites_chrm, sites_loci, gainp, lossp) {

    gene_hits=0; # set counter to zero
    tsg_hits=0;
    genes=c();
    
    for (i in 1:length(unique(sites_chrm))) { # loop over chromosomes inserted into
        
        tmp=anno[anno$chrom==unique(sites_chrm)[i],] # reduce annotation table to entries for current chrom

        tmp2 = sites_loci[sites_chrm==unique(sites_chrm)[i]] # reduce insertion loci to entries for current chrom
        
        ins <- lapply(tmp2,between,tmp$start,tmp$end) # create logical for insertions, whether into non-tsg or not
        ins <- unlist(lapply(ins,which))
        
        if (length(ins)>0) {
            genes <- append(genes,tmp$geneSym[ins])
        }
        
        gene_hits=gene_hits+length(which(tmp$istsg[ins]==0)) # count the number of non-tsg insertions
        tsg_hits =tsg_hits +length(which(tmp$istsg[ins]==1)) # count the number of tsg insertions

    }

    if (gene_hits > 0 || tsg_hits > 0){
        r=r*(lossp^gene_hits)*(gainp^tsg_hits)
    }

    return(list(r,genes))
}


# PURPOSE: To call gen_sim.r with some probability (probability of transposition, tp) for a clone at a time step
#
# INPUT:
#   node        (data.tree node) current node of the data tree
#   sp          passenger mutation selection coefficient (<1)
#   sd          driver mutation selection coefficient (>1)
#
# OUTPUT: void
maybeTranspose <- function(node, sd, sp) {

    if (node$r[[1]]==0){ # if the division rate of the clone is zero, skip the node
        return()
    }
    
    # increase the number of cells by the existing number * the division rate factor
    nc <- node$ncells[length(node$ncells)] + round(node$ncells[length(node$ncells)]*node$r[[1]])
    
    # sample from binomial distribution for number of transpositions
    if (nc < 4.2e9) {ntrans <- rbinom(1,nc,cellP)} # rbinom() fails for large n
    else {ntrans <- nc*cellP} # If n is too large, use the expected number of events (mean of distribution)
    if (ntrans > 0) {
        simout <- gen_sim(ntrans)
        nc <- nc-ntrans
        for (i in 1:ntrans) {
            l<<-l+1
            r_tmp <- rank_clone(node$r, exann, lapply(simout,'[',i)[[1]], lapply(simout,'[',i)[[2]], sd, sp)
            tmp<-mapply(append, lapply(simout,'[',i), node$tes, SIMPLIFY = FALSE)
            node$AddChild(l, ncells=1, r=r_tmp[[1]], genes=append(node$genes,r_tmp[[2]]), tes=tmp)
        }
    }   
    node$ncells <- append(node$ncells,nc)
}



#--- Set simulation parameters
######################################################################################

ENifrc<- .1       # Fraction of endonuclease-independent (random) insertions
rootNCells <- 1   # Initial number of cells in root clone
rootDivRate <- 1  # Initial division rate
cellP <- 0.2  # Probability of transposition / timestep of a single cell

NT <- args[2]     # Number of time steps

#--- Generate clone tree
######################################################################################

if (args[1]=='batch') {
    sd <- c(1/seq(1.0,0.2,-0.2))
    sp <- seq(1.0,0.2,-0.2)
	nrun <- 0
	for (sdi in 1:5) {
		for (spi in 1:5) {
		    l<-1 # Clone counter
		    CellPop <- Node$new(1)
		    CellPop$ncells <- c(rootNCells)
		    CellPop$r <- rootDivRate
		    CellPop$tes <- list(c(),c(),c(),c())
            CellPop$genes <- c()
		    # CellPop$tes <- list(DNAStringSet(c("TCGA")),c("chr1"),c(1013467),c("+"),c(0))
		    # CellPop$r <- rank_clone(CellPop$r, exann, CellPop$tes[[2]], CellPop$tes[[3]], 1.2, 0.8)
		    # CellPop$r

		    ptm <- proc.time()
		    for (n in 2:NT) {

		            CellPop$Do(maybeTranspose,sd[sdi],sp[spi])

		    }
		    print(proc.time() - ptm)

		    save("CellPop",file=paste0(args[3],nrun,".rda"))
		    rm(CellPop)
		    nrun <- nrun+1

		}

	}
} else if (args[1] == 'single') {

    l<-1 # Clone counter
	CellPop <- Node$new(1)
	CellPop$ncells <- c(rootNCells)
	CellPop$r <- rootDivRate
	CellPop$tes <- list(c(),c(),c(),c())
    CellPop$genes <- c()

	# CellPop$tes <- list(DNAStringSet(c("TTATTTA")),c("chr1"),c(1001140),c("+"),c(0))
	# CellPop$r <- rank_clone(CellPop$r, exann, CellPop$tes[[2]], CellPop$tes[[3]])
	# CellPop$r

	ptm <- proc.time()
	for (i in 2:NT) {

	    CellPop$Do(maybeTranspose,1.25,0.8)
	               
	}
	proc.time() - ptm

	save(CellPop, file=paste0(args[3]))

} else if (args[1] == 'endless') {
    
    l<-1 # Clone counter
	CellPop <- Node$new(1)
	CellPop$ncells <- c(rootNCells)
	CellPop$r <- rootDivRate
    CellPop$tes <- list(c(),c(),c(),c())
    CellPop$genes <- c()

	while (1) {
		ptm <- proc.time()

	    CellPop$Do(maybeTranspose,1.25,0.8)
		save(CellPop, file=paste0(args[3]))              

		print(proc.time()-ptm)

}
}




