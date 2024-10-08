// run manta structural variant detection and convert inversions
// change the workflow from germline to tumor_only mode
// tumor-only mode outputs a single vcf file tumorSV.vcf.gz
// Here, I did not change  original variable name (diploidSV), bear in mind that this is actually tumorSV now.
process manta {
	debug false
	publishDir "${params.outDir}/${sampleID}", mode: 'copy'

	input:
	tuple val(sampleID), file(bam), file(bai)
	path(ref)
	path(ref_fai)

	output:
	tuple val(sampleID), path("manta/Manta_${sampleID}.diploidSV.vcf.gz")					, emit: manta_diploid
	tuple val(sampleID), path("manta/Manta_${sampleID}.diploidSV.vcf.gz.tbi")				, emit: manta_diploid_tbi
	tuple val(sampleID), path("manta/Manta_${sampleID}.diploidSV_converted.vcf.gz")			, emit: manta_diploid_convert
	tuple val(sampleID), path("manta/Manta_${sampleID}.diploidSV_converted.vcf.gz.tbi")		, emit: manta_diploid_convert_tbi

	script:
	def extraArgs = params.extraMantaFlags ?: ''
	def intervals = params.intervals ? "--callRegions $params.intervals" : ''
	"""
	# configure manta SV analysis workflow
	configManta.py \
		--tumorBam ${bam} \
		--referenceFasta ${params.ref} \
		--runDir manta \
		${intervals} ${extraArgs}

	# run SV detection 
	manta/runWorkflow.py -m local -j ${task.cpus}

	# clean up outputs (didn't changed the output name to tumorSV)
	mv manta/results/variants/tumorSV.vcf.gz \
		manta/Manta_${sampleID}.diploidSV.vcf.gz
	mv manta/results/variants/tumorSV.vcf.gz.tbi \
		manta/Manta_${sampleID}.diploidSV.vcf.gz.tbi
	
	# convert multiline inversion BNDs from manta vcf to single line
	convertInversion.py \$(which samtools) ${params.ref} \
		manta/Manta_${sampleID}.diploidSV.vcf.gz \
		> manta/Manta_${sampleID}.diploidSV_converted.vcf

	# zip and index converted vcf
	bgzip manta/Manta_${sampleID}.diploidSV_converted.vcf
	tabix manta/Manta_${sampleID}.diploidSV_converted.vcf.gz
	"""
} 

// rehead manta SV vcf for merging 
process rehead_manta {
	debug false 
	publishDir "${params.outDir}/${sampleID}/manta", mode: 'copy'

	input:
	tuple val(sampleID), path(manta_diploid_convert)
	tuple val(sampleID), path(manta_diploid_convert_tbi)

	output:
	tuple val(sampleID), path("Manta_*.vcf")	, emit: manta_VCF
		
	script:
	"""
	# create new header for merged vcf
	printf "${sampleID}_manta\n" > ${sampleID}_rehead_manta.txt

	# replace sampleID with caller_sample for merging
	bcftools reheader \
		Manta_${sampleID}.diploidSV_converted.vcf.gz \
		-s ${sampleID}_rehead_manta.txt \
		-o Manta_${sampleID}.vcf.gz

	# gunzip vcf
	gunzip Manta_${sampleID}.vcf.gz
	"""
}
