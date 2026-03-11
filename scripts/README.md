## Source

Discussion in the IHP Open PDK repository:

https://github.com/IHP-GmbH/IHP-Open-PDK/issues/647

Issue:
**Add prBoundary.boundary (189/4) bounding box to top-level SRAM macro cells**

## Usage

Add `prBoundary` to a SRAM macro using KLayout:

nix-shell -p klayout --run 'klayout -zz -rm add_prboundary.py
-rd GDS=macro/RM_IHPSG13_1P_256x64_c2_bm_bist/RM_IHPSG13_1P_256x64_c2_bm_bist.gds
-rd LEF=macro/RM_IHPSG13_1P_256x64_c2_bm_bist/RM_IHPSG13_1P_256x64_c2_bm_bist.lef
-rd OUT=macro/RM_IHPSG13_1P_256x64_c2_bm_bist/RM_IHPSG13_1P_256x64_c2_bm_bist.fixed.gds'
