# Experimental Cluster EAs

This directory contains duplicate Expert Advisors that integrate the staging and clustering flow described in the MQL5 article *Developing a multi-currency Expert Advisor (Part 19)*.

| Original EA                    | Cluster Variant Path                                 | Notes                                      |
|--------------------------------|------------------------------------------------------|--------------------------------------------|
| `MainACAlgorithm.mq5`          | `AC_PipelineProtoCluster/experimental_cluster/MainACAlgorithm_Cluster.mq5`   | Stage-1 optimisation logging to SQLite.    |
| `ACBreakRevertPro.mq5`         | `AC_PipelineProtoCluster/experimental_cluster/ACBreakRevertPro_Cluster.mq5`  | Stage-1 optimisation logging to SQLite.    |
| `AC_SBS_Base.mq5`              | `AC_PipelineProtoCluster/experimental_cluster/AC_SBS_Base_Cluster.mq5`       | Stage-1 SBS optimisation logging to SQLite. |

All variants depend on the upstream `ClusteringLib` modules (see `AC_PipelineProtoCluster/ClusteringLib/`). When running tests in MetaTrader, ensure that:

1. The duplicate EA inputs point to the target SQLite database file managed by the `ClusteringLib` routines.
2. The `ClusteringStage1.py` script is executed between stage 1 and stage 2 to populate `passes_clusters`.
3. Post-optimisation backtests are exported from MT5 (HTML/CSV) for QuantAnalyzer review.
