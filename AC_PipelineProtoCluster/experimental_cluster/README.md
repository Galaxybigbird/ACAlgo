# Experimental Cluster EAs

This directory contains duplicate Expert Advisors that integrate the staging and clustering flow described in the MQL5 article *Developing a multi-currency Expert Advisor (Part 19)*.

## Stage‑1 logging EAs
| Original EA                    | Cluster Variant Path                                               | Notes                                      |
|--------------------------------|--------------------------------------------------------------------|--------------------------------------------|
| `MainACAlgorithm.mq5`          | `AC_PipelineProtoCluster/experimental_cluster/MainACAlgorithm_Cluster.mq5`          | Persists optimisation passes to SQLite.    |
| `ACBreakRevertPro.mq5`         | `AC_PipelineProtoCluster/experimental_cluster/ACBreakRevertPro_Cluster.mq5`         | Persists optimisation passes to SQLite.    |
| `AC_SBS_Base.mq5`              | `AC_PipelineProtoCluster/experimental_cluster/AC_SBS_Base_Cluster.mq5`              | Persists optimisation passes to SQLite.    |

## Stage‑2 portfolio EAs
| Base EA                                | Cluster Variant Path                                                           | Notes                                                                 |
|----------------------------------------|---------------------------------------------------------------------------------|-----------------------------------------------------------------------|
| `ACMultiSymbolAlgorithm.mq5`           | `AC_PipelineProtoCluster/experimental_cluster/ACMultiSymbolAlgorithm_Cluster.mq5`           | Adds `useClusters_` filtering for selecting distinct passes per cluster. |
| `DifferentEAs/ACMultiSACBreakRevertPro.mq5` | `AC_PipelineProtoCluster/experimental_cluster/ACMultiSACBreakRevertPro_Cluster.mq5` | Adds `useClusters_` filtering for multi-symbol BreakRevert portfolios.  |

All variants depend on the upstream `ClusteringLib` modules (see `AC_PipelineProtoCluster/ClusteringLib/`).

### Recommended workflow
1. Run the appropriate `_Cluster` Stage‑1 EA with `idTask_` / `fileName_` configured so every optimisation pass is written to the SQLite database.
2. Execute `AC_PipelineProtoCluster/ClusteringLib/ClusteringStage1.py` for the relevant `id_task`/`--id_parent_job` to fill the `passes_clusters` table.
3. Optimise or back-test the Stage‑2 portfolio `_Cluster` EA with `useClusters_ = true` (and optional filters) so each cluster contributes at most one pass. Set `useClusters_ = false` to fall back to the original selection logic.
4. For any shortlisted portfolios, run a single back-test, export the MT5 HTML/CSV report, and load it into QuantAnalyzer (or your analytics stack).
