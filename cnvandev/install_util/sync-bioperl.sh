#!/bin/bash
#syncs files that are already in extras/BioPerl/Bio with a bioperl-live
#cvs repository, while ignoring files that cvs would ignore
#This is  expecting to be run from the root of the gbrowse cvs repository
rsync -Ca --existing  ../bioperl-live/Bio/ extras/BioPerl/Bio/
