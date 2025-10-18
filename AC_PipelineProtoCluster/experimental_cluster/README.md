# Experimental Cluster EAs

This directory contains duplicate Expert Advisors that integrate the staging and clustering flow described in the MQL5 article *Developing a multi-currency Expert Advisor (Part 19)*.

## Stage‑1 logging EAs
| Original EA                    | Cluster Variant Path                                               | Notes                                      |
|--------------------------------|--------------------------------------------------------------------|--------------------------------------------|
| `MainACAlgorithm.mq5`          | `AC_PipelineProtoCluster/experimental_cluster/MainACAlgorithm_Cluster.mq5`          | Persists optimisation passes to SQLite.    |
| `ACBreakRevertPro.mq5`         | `AC_PipelineProtoCluster/experimental_cluster/ACBreakRevertPro_Cluster.mq5`         | Persists optimisation passes to SQLite.    |
| `AC_SBS_Base.mq5`              | `AC_PipelineProtoCluster/experimental_cluster/AC_SBS_Base_Cluster.mq5`              | Persists optimisation passes to SQLite.    |

## Stage‑2 portfolio EAs
| Stage‑1 Source EA          | Stage‑2 Variant Path                                                                       | Notes                                                                                 |
|---------------------------|---------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------|
| `MainACAlgorithm.mq5`     | `AC_PipelineProtoCluster/experimental_cluster/MainACAlgorithm_Stage2_Cluster.mq5`          | Builds a portfolio score from logged passes; `useClusters_` enforces per-cluster picks. |
| `ACBreakRevertPro.mq5`    | `AC_PipelineProtoCluster/experimental_cluster/ACBreakRevertPro_Stage2_Cluster.mq5`         | Same selector flow tailored to BreakRevertPro optimisation results.                    |
| `AC_SBS_Base.mq5`         | `AC_PipelineProtoCluster/experimental_cluster/AC_SBS_Base_Stage2_Cluster.mq5`              | Stage‑2 selector for SBS passes with clustering-aware filtering.                       |

All variants depend on the upstream `ClusteringLib` modules (see `AC_PipelineProtoCluster/ClusteringLib/`).

## Database initialisation
- The live optimisation database lives in your MT5 data directory at  
  `C:\Users\marth\AppData\Roaming\MetaQuotes\Terminal\E62C655ED163FFC555DD40DBEA67E6BB\MQL5\Files\database.sqlite`.
- Run `python scripts/init_ac_pipeline_db.py` to recreate the database from the canonical schema located in `MQL5\Include\ClusteringLib\database.sqlite.schema.sql`.  
  The script accepts `--schema` and `--database` overrides if you need a different terminal instance.
- Stage‑1 `_Cluster` EAs now default their `fileName_` input to this absolute path, so you only need to supply an `idTask_` when optimising.

### Recommended workflow
1. Run the appropriate `_Cluster` Stage‑1 EA with a valid `idTask_`; the default `fileName_` already targets the database above so every optimisation pass is written to SQLite.
2. Execute `AC_PipelineProtoCluster/ClusteringLib/ClusteringStage1.py` for the relevant `id_task`/`--id_parent_job` to fill the `passes_clusters` table.
3. Optimise or back-test the Stage‑2 portfolio `_Cluster` EA with `useClusters_ = true` (and optional filters) so each cluster contributes at most one pass. Set `useClusters_ = false` to fall back to the original selection logic.
4. For any shortlisted portfolios, run a single back-test, export the MT5 HTML/CSV report, and load it into QuantAnalyzer (or your analytics stack).
