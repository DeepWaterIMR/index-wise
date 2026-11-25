# Job resources per stock, from a pilot of the whole unit of work (fit + index prediction +
# saving) of the most demanding candidate on the server (hpc-wise hpc-estimate). Re-read by
# the driver before every submission, so an edit applies to the next try of a running driver.
# Billing per task-hour = max(cpus, 0.34 x GiB requested); unused time is refunded.
# Lessons (ling/tusk 2026): the index prediction after the fit can double peak memory; AR1/RW
# candidates with extra time steps need more memory than IID; combining a stage (assemble)
# needs tens of GB on fine meshes.
ASM_MEM=16G; ASM_TIME=02:00:00
FIT_MEM=7000M;  FIT_TIME=02:00:00
RETRY_MEM_FACTOR=2        # a failed candidate retries with twice the memory
CV_CPUS=10;     CV_MEM=3000M;  CV_TIME=03:00:00
MESH_FINE_KM=0            # a cutoff (km) that runs as its own array with CV_MEM_FINE/CV_TIME_FINE; 0 = none
CV_MEM_FINE=6000M; CV_TIME_FINE=12:00:00
CV_MEM_MESH=3000M; CV_TIME_MESH=04:00:00
case "$SPECIES" in
  # <stock>) FIT_MEM=9000M; CV_MEM=4000M ;;   # per-stock overrides from its pilot
  *) ;;
esac
