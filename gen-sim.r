#!/usr/bin/env Rscript

# -----------------------------------------------------------------------------
# gen-sim.r

# Entry point for simulating retrotransposition of L1 elements on hg38.
#
# This script loads a file representing a series of 4x24 arrays that's generated 
# by 'get_sv_dist.r'. It uses this to calculate a 'probability of insertion' 
# vector for the chromosomes specified. 
# 
# Insertion site probabilities are based on the 'Snap-Velcro model' described 
# in Clement Monot, et al. (2013) "The Specificity and Flexibility of L1 Reverse 
# Transcription Priming at Imperfect T-Tracts." PLOS Genetics, 9:5.
#
# This script does two things:
#	* Selects the insertion sites.
#	* Prepares the sequences for insertion.
#
# Dependencies: R(>= 2.8.0, Packages - Biostrings, BSgenome (for default hg38), 
# GenomicRanges)
# -----------------------------------------------------------------------------

#--- Load libraries
library(Biostrings)
library(BSgenome.Hsapiens.UCSC.hg38)
library(GenomicRanges)

args<-commandArgs(trailingOnly=TRUE)
 
copyNum <- args[1] # args[1] is number of genome-wide insertions.

#--- An endonuclease encoded by L1 is normally required for retrotransposition
# to occur. The following variable represents the allowed fraction of 
# endonuclease-independent insertions and is currently modeled as occurring 
# in random locations. This fraction of ENi insertions is tunable, default is 0.1.  
ENifrc <- 0.1

genome <- Hsapiens # hg38 human genome. 

cat("\nCopy number: ",copyNum,"\n")
cat("ENi insertion fraction: ",ENifrc,"\n")

sites_loci<-c() # Initialize arrays for storing simulated ins. site data
sites_chrm<-c()
sites_strand<-c()
sites_classes<-c()
strdict<-c("+","-") 
names(strdict)<-c(1,2)

#--- Sample chromosomes based on probability ranking. The data file chrmpd.rda 
# must either be provided or generated by running 'get_sv_dist.r'.
load("./data/chrmpd.rda")

#---  Here the ranking is provided by the number of 'TTTT' patterns.
chrmlist<-sample(x=names(genome)[1:24],copyNum,replace=TRUE,prob=chrmcnt[,1])
chrmlist<-table(chrmlist)
cat("\nChromosomes: ",names(chrmlist),"\n")

#--- Load map file for chosen chromosomes
for (i in names(chrmlist)) {
	cat("\nLoading map file...")
	load(paste0("./data/root_maps/",i,"map.rda"))
}
cat("\n")

ptm <- proc.time() # Begin timer


for (chrnm in names(chrmlist)) {
	
	cat("\nChromosome: ",chrnm)

	ict<-get(paste0(chrnm,"ict"))
	icl<-get(paste0(chrnm,"icl"))
	iot<-get(paste0(chrnm,"iot"))
	iol<-get(paste0(chrnm,"iol"))
	insites<-get(paste0(chrnm,"insites"))

	chrcopyNum<-chrmlist[[chrnm]]

	pd <- c(11.55*length(which(!is.na(ict))),7.25*length(which(!is.na(icl))),1.95*length(which(!is.na(iot))),1*length(which(!is.na(iol))))
	pd <- (pd/sum(pd))*(1-ENifrc)
	pd <- append(pd,ENifrc)
	cat("\nSite class distribution:\n",pd)

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

	cat("\nInsertion sites:\n")
	cat(sites,"\n")
	#cat("Site targets:\n")
	#for (i in 1:copyNum) {
	#	print(chr[(sites[i]-3):sites[i]])
	#}
	sites_loci<-append(sites_loci,sites)
	sites_chrm<-append(sites_chrm,rep(chrnm,chrcopyNum))
	sites_strand<-append(sites_strand,strand)
	sites_classes<-append(sites_classes,classes)
}
rm(ict,icl,iot,iol,insites) # clean up

#--- Creates sequences for insertion
load("./data/L1RankTable.rda")
L1RankTable$score[1:40] <- L1RankTable$score[1:40]/sum(L1RankTable$score[1:40])
l1indcs <- sample(x=c(1:40),copyNum,replace=TRUE,prob=L1RankTable$score[1:40])
trpd <- read.table("./data/L1truncpd.csv",sep=",")
tdpd <- read.table("./data/L1transdpd.txt",sep="\t")
trfrcv <- sample(x = trpd[[1]], copyNum, replace = TRUE, prob = trpd[[2]])
tdlenv <- sample(x = tdpd[[1]], copyNum, replace = TRUE, prob = tdpd[[2]])
trlenv<-rep(0,copyNum)

for (i in 1:copyNum) {
	len <- L1RankTable[[3]][l1indcs[i]]-L1RankTable[[2]][l1indcs[i]]
	trlenv[i] <- ceiling(len*trfrcv[i])
}

gr <- GRanges(L1RankTable[[1]][l1indcs],IRanges(L1RankTable[[2]][l1indcs]+trlenv,L1RankTable[[3]][l1indcs]+tdlenv),strand=L1RankTable[[5]][l1indcs])
l1s <- getSeq(genome,gr)
cat("\nRunning time:\n")
proc.time() - ptm
cat("\nSaving image...\n")

#--- Saves all to file 'gen-sim-out.rda'
save(tdlenv,trlenv,l1s,l1indcs,sites_loci,sites_chrm,sites_strand,sites_classes,file="./data/gen-sim-out.rda")

