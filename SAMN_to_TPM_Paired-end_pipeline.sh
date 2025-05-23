#!/bin/bash --login
########## Define Resources Needed with SBATCH Lines ##########

#SBATCH --account="Your User Name"
#SBATCH --array=0-Int               # replace Int as a specific number; for example: 500 array threads that will run in parallel
#SBATCH --time=4:00:00             # limit of wall clock time - how long the job will run (same as -t)
#SBATCH --nodes=1                  
#SBATCH --ntasks=1                  # number of tasks - how many tasks (nodes) that you require (same as -n)
#SBATCH --cpus-per-task=2           # number of CPUs (or cores) per task (same as -c)
#SBATCH --mem-per-cpu=5G
#SBATCH --job-name  Paired-end_TPM               # you can give your job a name for easier identification (same as -J)
#SBATCH --output=%x_%j.out # output (%x is the --job-name and %j is the job id); there will be 100 output files, one for each thread
 
########## Command Lines to Run ##########

#Step1: give each sample name to get all SRR info
SAMPLE=( "Your sample name list" )

echo "${SLURM_ARRAY_TASK_ID} ; ${SAMPLE[${SLURM_ARRAY_TASK_ID}]}" # iterate throught the list SAMPLE (length of 500 elements)

cd "Your work directory"

module load Trimmomatic/0.38-Java-1.8

ADAPTER="adapters under Trimmomatic"
REF="path of your Arabidopsis hisat reference file"
RESULT="path where you want to put your fpkm results"
PAIRED="path where you want to put your process file"

mkdir -p ~/.ncbi
echo '/repository/user/main/public/root = "/scratch/standage/sra-cache"' > ~/.ncbi/user-settings.mkfg

time for i in ${SAMPLE[${SLURM_ARRAY_TASK_ID}]};
do mkdir ${i};
cd ${i};
echo $i;
srr="$(esearch -db sra -query $i | efetch -format runinfo | cut -d "," -f 1 | grep SRR)";
echo $srr >> ${i}_SRR_namelist;
sed -i 's/ /\n/g' ${i}_SRR_namelist; 
wc -l ${i}_SRR_namelist | awk '{if($1<1){print "SRR number is Wrong"}}';

#Step2: download fastq file of each SRR
for j in `cat ${i}_SRR_namelist`;
do echo $j;
fasterq-dump --split-files ${j};
done

#Step3: merge all fastq raw files
touch ${i}_1.fastq
touch ${i}_2.fastq
for m in `cat ${i}_SRR_namelist`;
do cat ${i}_1.fastq ${m}_1.fastq > ${i}_1_temp.fastq
mv ${i}_1_temp.fastq ${i}_1.fastq
cat ${i}_2.fastq ${m}_2.fastq > ${i}_2_temp.fastq
mv ${i}_2_temp.fastq ${i}_2.fastq
done
ls -lth *fastq

#Step4: remove each SRR fastq file
for m in `cat ${i}_SRR_namelist`;
do /bin/rm ${m}_?.fastq;
done

#Step5: guess qulity phred score
VAL=$(head -n 40 ${i}_1.fastq | awk '{if(NR%4==0) printf("%s",$0);}' | od -A n -t u1 | awk 'BEGIN{min=100;max=0;}{for(i=1;i<=NF;i++) {if($i>max) max=$i; if($i<min) min=$i;}}END{if(max<=74 && min<59) print "Phred+33"; else if(max>73 && min>=64) print "Phred+64"; else if(min>=59 && min<64 && max>73) print "Solexa+64"; else print "Unknown score";}' | sed 's/Phred+//g' | sed 's/Solexa+//g')

if [ $VAL -eq 33 ] || [ $VAL -eq 64 ]; then echo "$i qulity phred is $VAL"; else echo "$i qulity phred is Wrong"; fi

#Step6: Run Trimmomatic; remove all possible adapter and set Q=30 as cutoff
java -jar $EBROOTTRIMMOMATIC/trimmomatic-0.38.jar PE -phred${VAL} \
${i}_1.fastq ${i}_2.fastq \
trimmed-${i}_1.fastq.gz ${i}_1.unpaired.fastq.gz \
trimmed-${i}_2.fastq.gz ${i}_2.unpaired.fastq.gz \
-threads 10 ILLUMINACLIP:${ADAPTER}/TruSeq-All-PE.fa:2:30:10 \
LEADING:30 TRAILING:30 SLIDINGWINDOW:4:30 MINLEN:20
ls -lth *fastq*
/bin/rm ${i}_?.fastq

#Step7: Run Samlon for TPM and ReadCount
time salmon quant \
-i ${REF}/salmon_index \
-l A \
-1 trimmed-${i}_1.fastq.gz \
-2 trimmed-${i}_2.fastq.gz \
--validateMappings \
-o ${i}_quant 

tar -zcvf ${i}_quant.tar.gz ${i}_quant
cp ${i}_quant.tar.gz ${RESULT}/

cd ${PAIRED}
if [ -e ${RESULT}/${i}_quant.tar.gz ]; then
 echo "$i TPM and ReadCount is Done"
 /bin/rm -rf ${PAIRED}/${i}
else
 echo "$i TPM is Wrong"
fi

echo "${i} Finished!!!!"
echo "\n"

done

scontrol show job $SLURM_JOB_ID # information about the job and each thread
