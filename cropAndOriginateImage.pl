#!/usr/bin/perl -w

use strict;

use File::Basename;
use File::Copy;
use File::Path;
use Getopt::Long;

use FindBin qw($Bin);

my $usage = qq{
  $0
     --input
     --template
     --template-coverage-mask
     --output
     [options]

  Crop an image and set the origin from a template. This makes images more consistent in terms of origin and FOV, which 
  helps template construction and possibly other processing.

  This code calls antsAI with translation, so your ANTSPATH should point to an installation that has that.


  
  Required args:
     --input
       Head image to be processed.

     --template
       Template, assumed to be the same modality (use CC as the deformable metric).

     --template-coverage-mask
       A mask covering the desired bounding box in the template space.

     --output
       Output image file name.
  
  Options:
     --template-reg-mask
       Registration mask in the template space. This may be different to the coverage mask.

     --bias-correct
       Winsorize outliers and run N4 on the input image (default = 1).

     --quick
       Quicker registration (default = 0).

     --float 
       Use float precision (default = 1).

  Requires ANTs (set ANTSPATH) and ANTsR (library(ANTsR) should work).
};


if ($#ARGV < 0) {
    print $usage;
    exit 1;
}

# Get the directories containing programs we need
my ($antsPath, $sysTmpDir) = @ENV{'ANTSPATH', 'TMPDIR'};


if (!$antsPath || ! -f "${antsPath}antsRegistration") {
    die("Script requires ANTSPATH to be defined");
}

# Required args
my ($inputHead, $template, $templateCoverageMask, $outputFile);

# Optional args have defaults
my $useTemplateRegMask = 0;
my $templateRegMask = "";
my $doN4 = 1;
my @segPriors = ();
my $useFloatPrecision = 1;
my $quick = 0;

GetOptions ("input=s" => \$inputHead,
	    "output=s" => \$outputFile,
            "template=s" => \$template,
	    "template-coverage-mask=s" => \$templateCoverageMask,
	    "template-reg-mask=s" => \$templateRegMask,
	    "bias-correct=i" => \$doN4,
	    "float=i" => \$useFloatPrecision,
            "quick=i" => \$quick
    )
    or die("Error in command line arguments\n");

if ( -f $templateRegMask ) {
    $useTemplateRegMask = 1;
}
 
my ($outputFileRoot,$outputDir) = fileparse($outputFile, ".nii.gz");

if (! -d $outputDir ) {
  mkpath($outputDir, {verbose => 0, mode => 0775}) or die "Cannot create output directory $outputDir\n\t";
}

# Set to 1 to delete intermediate files after we're done
my $cleanup=1;

# Directory for temporary files that is deleted later if $cleanup
my $tmpDir = "";

my $tmpDirBaseName = "${outputFileRoot}beReg";

if ( !($sysTmpDir && -d $sysTmpDir) ) {
    $tmpDir = $outputDir . "/${tmpDirBaseName}";
}
else {
    # Have system tmp dir
    $tmpDir = $sysTmpDir . "/${tmpDirBaseName}";
}

# Gets removed later, so check we can create this and if not, exit immediately
mkpath($tmpDir, {verbose => 0, mode => 0755}) or die "Cannot create working directory $tmpDir (maybe it exists from a previous run)\n\t";

# Copy of input we can work on
my $headImage = "${tmpDir}/head.nii.gz";

if ($doN4) {
    my $truncateMask = "${tmpDir}/intensityMask.nii.gz";
    
    # Truncate intensity idea copied from antsBrainExtraction.sh, useful for T1, not sure about other modalities
    # Attempt to make quantiles insensitive to amount of background
    system("${antsPath}ImageMath 3 $truncateMask Normalize $inputHead 1");
    system("${antsPath}ThresholdImage 3 $truncateMask $truncateMask 0.5 Inf");
    system("${antsPath}ImageMath 3 $headImage TruncateImageIntensity $inputHead -1.0 0.995 256 $truncateMask");
    system("${antsPath}N4BiasFieldCorrection -d 3 -i $headImage -s 4 -c [50x50x50x50,0.0000001] -b [200] -o $headImage --verbose 1");
}
else {
    copy($inputHead, $headImage);
}


# Get initial moving transform to template


my $antsAffInitRes = "5 5 5";
my $antsAffInitSmooth = "3";

my $downsampleTemplate = "${tmpDir}/templateDownsample.nii.gz";
my $downsampleHeadImage = "${tmpDir}/headDownsample.nii.gz";
my $downsampleRegMask = "${tmpDir}/templateRegMaskDownsample.nii.gz";

system("${antsPath}SmoothImage 3 $template $antsAffInitSmooth ${tmpDir}/templateSmooth.nii.gz  1");
system("${antsPath}SmoothImage 3 $headImage $antsAffInitSmooth ${tmpDir}/headSmooth.nii.gz 1");

system("${antsPath}ResampleImageBySpacing 3 ${tmpDir}/templateSmooth.nii.gz $downsampleTemplate $antsAffInitRes 0");
system("${antsPath}ResampleImageBySpacing 3 ${tmpDir}/headSmooth.nii.gz $downsampleHeadImage $antsAffInitRes 0");

my $initialAffine = "${tmpDir}/initialAffine.mat";

# -s [ searchFactor, arcFraction ]
# searchFactor = step size
# arcFraction = fraction of arc to search 1 = +/- 180 degrees, 0.5 = +/- 90 degrees
#
my $antsAICmd = "${antsPath}antsAI -d 3 -v 1 -m Mattes[$downsampleTemplate, $downsampleHeadImage, 32, Regular, 0.2] -t Affine[0.1] -s [20, 0.12] -c 10 -g [40, 0x40x40] -o $initialAffine";


if ($useTemplateRegMask) {

    system("${antsPath}ResampleImageBySpacing 3 $templateRegMask $downsampleRegMask $antsAffInitRes 0 0 1");

    $antsAICmd = "$antsAICmd -x $downsampleRegMask";
    
}

print "\n--- ANTs AI ---\n${antsAICmd}\n---\n";

system($antsAICmd);

my $transformPrefix = "${tmpDir}/headToTemplate";

my $affineRegMaskString = "";

if ($useTemplateRegMask) {
    $affineRegMaskString = "-x $templateRegMask";
}

my $histogramMatch = 1;

# Affine init should get most of rigid but refine a little
my $rigidIts = "50x25x0";

# Some more affine
my $affineIts = "100x100x50x0";

if ($quick) {
  $rigidIts = "25x10x0";
  $affineIts = "50x50x10x0";
}

my $regAffineCmd = "${antsPath}antsRegistration -d 3 -u $histogramMatch -w [0, 0.999] --verbose --float $useFloatPrecision -o $transformPrefix -r $initialAffine -t Rigid[0.1] -m Mattes[$template, $headImage, 1, 32, Regular, 0.2] -f 4x2x1 -s 2x1x0mm -c [${rigidIts},1e-7,10] $affineRegMaskString -t Affine[0.1] -m Mattes[$template, $headImage, 1, 32, Regular, 0.2] -f 6x4x2x1 -s 3x2x1x0mm -c [${affineIts},1e-7,10] $affineRegMaskString";


print "\n--- Registration ---\n${regAffineCmd}\n---\n";

system($regAffineCmd);

# Now call R code to originate and crop
system("${Bin}/cropImageToMask.R --input $headImage --template $template --template-coverage-mask $templateCoverageMask --transform ${transformPrefix}0GenericAffine.mat --output ${outputFile}");


if ($cleanup) {
    system("rm ${tmpDir}/*");
    system("rmdir $tmpDir");
}
