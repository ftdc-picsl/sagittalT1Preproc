## Find rectangular bounding box in voxel coordinates (can be used to subset an array)
## Finds box bounding region with any voxel > 0
## Assumes 3D input
findBB <- function(image) {

  size = dim(image)

  bbMin = c(size[1], size[2], size[3])

  bbMax = c(1,1,1)

  for (sliceDim in 1:3) { 
    
    sliceVoxels = list(1:size[1], 1:size[2], 1:size[3])

    sliceIndex = 1

    while (sliceIndex <= size[sliceDim]) {

      sliceVoxels[[sliceDim]] = sliceIndex
      
      if (max(image[sliceVoxels[[1]], sliceVoxels[[2]], sliceVoxels[[3]]]) > 0) {
        bbMin[sliceDim] = sliceIndex
        break  
      }

      sliceIndex = sliceIndex + 1
      
    }
    
    sliceIndex = size[sliceDim]
    
    while (sliceIndex >= 1) {

      sliceVoxels[[sliceDim]] = sliceIndex
      
      if (max(image[sliceVoxels[[1]], sliceVoxels[[2]], sliceVoxels[[3]]]) > 0) {
        bbMax[sliceDim] = sliceIndex
        break  
      }

      sliceIndex = sliceIndex - 1
      
    }
    
  }

  return(list(bbMin = bbMin, bbMax = bbMax))

}


## Crop an image to the specified bounding box, and adjust origin
cropToBB <- function(image, bbMin, bbMax) {

  print(paste("Cropping to bounding box min:", paste(bbMin, collapse = ","), "max:", paste(bbMax, collapse = ",")))
  
  croppedOrigin = as.numeric(antsTransformIndexToPhysicalPoint(image, bbMin))
  
  arr = as.array(image)

  arrCrop = arr[bbMin[1]:bbMax[1], bbMin[2]:bbMax[2], bbMin[3]:bbMax[3]]

  imCrop = as.antsImage(arrCrop, reference = image)

  antsSetOrigin(imCrop, croppedOrigin)

  return(imCrop)

}


setOriginFromTemplate <- function(fixed, moving, affineTransform = NULL) {

  ## Get the origin approximately correct or at least consistent with other longitudinal images

  ## Do quick registration if warps is null
  if (is.null(affineTransform)) {
    warps = antsRegistration(fixed = fixed, moving = moving, typeofTransform = "QuickRigid", verbose = T)
    affineTransform = warps$forwardTransforms
  }
  
  origin = matrix(c(0,0,0), ncol = 3, nrow = 1)
  
  originWarped = as.matrix(antsApplyTransformsToPoints(3, origin, transformlist = affineTransform, whichtoinvert = c(F)))

  originFix = antsImageClone(moving)
  
  antsSetOrigin(originFix, as.numeric(antsGetOrigin(moving) - originWarped))

  return(originFix)
  
}


