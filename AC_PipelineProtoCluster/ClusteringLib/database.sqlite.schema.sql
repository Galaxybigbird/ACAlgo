PRAGMA foreign_keys = off;
BEGIN TRANSACTION;

-- Table: jobs
DROP TABLE IF EXISTS jobs;

CREATE TABLE jobs (
    id_job        INTEGER PRIMARY KEY AUTOINCREMENT,
    id_stage      INTEGER REFERENCES stages (id_stage) ON DELETE CASCADE
                          NOT NULL,
    symbol        TEXT    DEFAULT EURGBP,
    period        TEXT    DEFAULT H1,
    tester_inputs TEXT,
    status        TEXT    CHECK (status IN ('Queued', 'Processing', 'Done') ) 
                          NOT NULL
                          DEFAULT Queued
);


-- Table: passes
DROP TABLE IF EXISTS passes;

CREATE TABLE passes (
    id_pass               INTEGER  PRIMARY KEY AUTOINCREMENT,
    id_task               INTEGER  REFERENCES tasks (id_task) ON DELETE CASCADE,
    pass                  INTEGER,
    is_optimization       INTEGER  CHECK (is_optimization IN (0, 1) ),
    is_forward            INTEGER  CHECK (is_forward IN (0, 1) ),
    initial_deposit       REAL,
    withdrawal            REAL,
    profit                REAL,
    gross_profit          REAL,
    gross_loss            REAL,
    max_profittrade       REAL,
    max_losstrade         REAL,
    conprofitmax          REAL,
    conprofitmax_trades   REAL,
    max_conwins           REAL,
    max_conprofit_trades  REAL,
    conlossmax            REAL,
    conlossmax_trades     REAL,
    max_conlosses         REAL,
    max_conloss_trades    REAL,
    balancemin            REAL,
    balance_dd            REAL,
    balancedd_percent     REAL,
    balance_ddrel_percent REAL,
    balance_dd_relative   REAL,
    equitymin             REAL,
    equity_dd             REAL,
    equitydd_percent      REAL,
    equity_ddrel_percent  REAL,
    equity_dd_relative    REAL,
    expected_payoff       REAL,
    profit_factor         REAL,
    recovery_factor       REAL,
    sharpe_ratio          REAL,
    min_marginlevel       REAL,
    deals                 REAL,
    trades                REAL,
    profit_trades         REAL,
    loss_trades           REAL,
    short_trades          REAL,
    long_trades           REAL,
    profit_shorttrades    REAL,
    profit_longtrades     REAL,
    profittrades_avgcon   REAL,
    losstrades_avgcon     REAL,
    complex_criterion     REAL,
    custom_ontester       REAL,
    params                TEXT,
    inputs                TEXT,
    pass_date             DATETIME
);


-- Table: projects
DROP TABLE IF EXISTS projects;

CREATE TABLE projects (
    id_project  INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    version     TEXT    NOT NULL,
    description TEXT,
    params      TEXT,
    status      TEXT    CHECK (status IN ('Created', 'Queued', 'Processing', 'Done') ) 
                        NOT NULL
                        DEFAULT Created
);


-- Table: stages
DROP TABLE IF EXISTS stages;

CREATE TABLE stages (
    id_stage               INTEGER PRIMARY KEY AUTOINCREMENT,
    id_project             INTEGER REFERENCES projects (id_project) ON DELETE CASCADE,
    id_parent_stage        INTEGER REFERENCES stages (id_stage) ON DELETE CASCADE,
    name                   TEXT    NOT NULL
                                   DEFAULT (1),
    expert                 TEXT,
    symbol                 TEXT    NOT NULL
                                   DEFAULT EURGBP,
    period                 TEXT    NOT NULL
                                   DEFAULT H1,
    optimization           INTEGER NOT NULL
                                   DEFAULT (2),
    model                  INTEGER NOT NULL
                                   DEFAULT (2),
    from_date              DATE    NOT NULL
                                   DEFAULT ('2022.01.01'),
    to_date                DATE    NOT NULL
                                   DEFAULT ('2022.06.01'),
    forward_mode           INTEGER NOT NULL
                                   DEFAULT (0),
    forward_date           DATE,
    deposit                INTEGER NOT NULL
                                   DEFAULT (10000),
    currency               TEXT    NOT NULL
                                   DEFAULT USD,
    profit_in_pips         INTEGER NOT NULL
                                   DEFAULT (0),
    leverage               INTEGER NOT NULL
                                   DEFAULT (200),
    execution_mode         INTEGER NOT NULL
                                   DEFAULT (0),
    optimization_criterion INTEGER NOT NULL
                                   DEFAULT (7),
    status                 TEXT    CHECK (status IN ('Queue', 'Process', 'Done') ) 
                                   NOT NULL
                                   DEFAULT 'Queue'
);


-- Table: strategy_groups
DROP TABLE IF EXISTS strategy_groups;

CREATE TABLE strategy_groups (
    id_pass INTEGER REFERENCES passes (id_pass) ON DELETE CASCADE
                                                ON UPDATE CASCADE
                    PRIMARY KEY,
    name    TEXT
);


-- Table: tasks
DROP TABLE IF EXISTS tasks;

CREATE TABLE tasks (
    id_task                INTEGER  PRIMARY KEY AUTOINCREMENT,
    id_job                 INTEGER  NOT NULL
                                    REFERENCES jobs (id_job) ON DELETE CASCADE,
    optimization_criterion INTEGER  DEFAULT (7) 
                                    NOT NULL,
    start_date             DATETIME,
    finish_date            DATETIME,
    status                 TEXT     CHECK (status IN ('Queued', 'Processing', 'Done') ) 
                                    NOT NULL
                                    DEFAULT Queued
);


-- Trigger: insert_empty_job
DROP TRIGGER IF EXISTS insert_empty_job;
CREATE TRIGGER insert_empty_job
         AFTER INSERT
            ON stages
          WHEN NEW.name = 'Single tester pass'
BEGIN
    INSERT INTO jobs VALUES (
                         NULL,
                         NEW.id_stage,
                         NULL,
                         NULL,
                         NULL,
                         'Done'
                     );
    INSERT INTO tasks (
                          id_job,
                          optimization_criterion,
                          status
                      )
                      VALUES (
                          (
                              SELECT id_job
                                FROM jobs
                               WHERE id_stage = NEW.id_stage
                          ),
-                         1,
                          'Done'
                      );
END;


-- Trigger: insert_empty_stage
DROP TRIGGER IF EXISTS insert_empty_stage;
CREATE TRIGGER insert_empty_stage
         AFTER INSERT
            ON projects
BEGIN
    INSERT INTO stages (
                           id_project,
                           name,
                           optimization,
                           status
                       )
                       VALUES (
                           NEW.id_project,
                           'Single tester pass',
                           0,
                           'Done'
                       );
END;


-- Trigger: reset_task_dates
DROP TRIGGER IF EXISTS reset_task_dates;
CREATE TRIGGER reset_task_dates
         AFTER UPDATE
            ON tasks
          WHEN OLD.status <> NEW.status AND 
               NEW.status = 'Queued'
BEGIN
    UPDATE tasks
       SET start_date = NULL,
           finish_date = NULL
     WHERE id_task = NEW.id_task;
END;


-- Trigger: upd_pass_date
DROP TRIGGER IF EXISTS upd_pass_date;
CREATE TRIGGER upd_pass_date
         AFTER INSERT
            ON passes
BEGIN
    UPDATE passes
       SET pass_date = DATETIME('NOW') 
     WHERE id_pass = NEW.id_pass;
END;


-- Trigger: upd_task_finish_date
DROP TRIGGER IF EXISTS upd_task_finish_date;
CREATE TRIGGER upd_task_finish_date
         AFTER UPDATE
            ON tasks
          WHEN OLD.status <> NEW.status AND 
               NEW.status = 'Done'
BEGIN
    UPDATE tasks
       SET finish_date = DATETIME('NOW') 
     WHERE id_task = NEW.id_task;
END;


-- Trigger: upd_task_start_date
DROP TRIGGER IF EXISTS upd_task_start_date;
CREATE TRIGGER upd_task_start_date
         AFTER UPDATE
            ON tasks
          WHEN OLD.status <> NEW.status AND 
               NEW.status = 'Processing'
BEGIN
    UPDATE tasks
       SET start_date = DATETIME('NOW') 
     WHERE id_task = NEW.id_task;
END;


COMMIT TRANSACTION;
PRAGMA foreign_keys = on;
