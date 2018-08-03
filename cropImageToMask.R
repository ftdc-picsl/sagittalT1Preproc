#!/share/apps/R/R-3.2.5/bin/Rscript

library("optparse")


##
## Gets the directory containing this script, either relative or absolute depending on how script was invoked
##
getBinDir <- function() {
    argv = commandArgs(trailingOnly = FALSE)
    binDir = dirname(substring(argv[grep("--file=", argv)], 8))
    return(binDir)
}

binDir = getBinDir()

source(paste(binDir, "cropImageToMaskHelper.R", sep = "/"))

args = commandArgs(trailingOnly=TRUE)

option_list = list(
  make_option("--input", type="character", default=NULL, dest="movingFile",
              help="Input image file", metavar="character"),
  make_option("--output", type="character", default=NULL, dest="outputFile",   
              help="Output image file", metavar="character"),
  make_option("--template", type="character", default=NULL, dest="templateFile",
              help="template image, used to place origin after crop", metavar="character"),
  make_option("--template-coverage-mask", type="character", default=NULL, dest="templateMask",
              help="Mask used to define the coverage that we wish to retain, in template space", metavar="character"),
  make_option("--transform", type="character", default=NULL, dest="transform",
              help="Affine forward transform used to warp moving image to the template", metavar="character")
); 
 
opt_parser = OptionParser(option_list=option_list,
  epilogue = "This script crops an image to the bounding box of a mask. Requires ANTsR.");

if (length(args)==0) {
  print_help(opt_parser)
  quit(save = "no")
}

library("ANTsR")

opt = parse_args(opt_parser);

mov = antsImageRead(opt$movingFile)
template = antsImageRead(opt$templateFile)
templateMask = antsImageRead(opt$templateMask)
transform = opt$transform

coverageSubj = antsApplyTransforms(mov, templateMask, transformlist = transform, interpolator = "nearestNeighbor", whichtoinvert = c(T), verbose = T)

originated = setOriginFromTemplate(template, mov, transform)

## Returns bounds in voxel space
boundingBox = findBB(coverageSubj)

## Crop the originated image, the origin will be updated
cropped = cropToBB(originated, boundingBox$bbMin, boundingBox$bbMax)

antsImageWrite(cropped, opt$outputFile)








