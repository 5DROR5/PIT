-- =============================================================================
-- PIT Economy System — Database Schema
-- Run this once to create all required tables.
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

CREATE TABLE IF NOT EXISTS players (
    uid                       VARCHAR(128)  NOT NULL,
    name                      VARCHAR(64)   NOT NULL DEFAULT 'Unknown',
    money                     BIGINT        NOT NULL DEFAULT 0,
    role                      VARCHAR(16)   NOT NULL DEFAULT 'civilian',
    lang                      VARCHAR(10)   NOT NULL DEFAULT NULL,
    player_rank               INT           NOT NULL DEFAULT 1,
    task_progress             TEXT                   DEFAULT NULL,
    is_wanted                 TINYINT(1)    NOT NULL DEFAULT 0,
    last_police_payment       BIGINT        NOT NULL DEFAULT 0,
    wanted_count              INT           NOT NULL DEFAULT 0,
    wanted_success            INT           NOT NULL DEFAULT 0,
    wanted_failed             INT           NOT NULL DEFAULT 0,
    police_arrests            INT           NOT NULL DEFAULT 0,
    total_chase_time_seconds  INT           NOT NULL DEFAULT 0,
    total_wanted_time_seconds INT           NOT NULL DEFAULT 0,
    markers_captured_police   INT           NOT NULL DEFAULT 0,
    markers_captured_wanted   INT           NOT NULL DEFAULT 0,
    total_money_earned        BIGINT        NOT NULL DEFAULT 0,
    total_money_spent         BIGINT        NOT NULL DEFAULT 0,
    total_playtime_seconds    INT           NOT NULL DEFAULT 0,
    login_count               INT           NOT NULL DEFAULT 0,
    created_at                DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen                 DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (uid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------------------------------
-- PartsShop module tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS purchased_parts (
    id           INT          NOT NULL AUTO_INCREMENT,
    uid          VARCHAR(128) NOT NULL,
    part_key     VARCHAR(128) NOT NULL,
    part_name    VARCHAR(128) NOT NULL DEFAULT '',
    price        INT          NOT NULL DEFAULT 0,
    purchased_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_uid_part (uid, part_key),
    FOREIGN KEY (uid) REFERENCES players(uid) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS free_vehicle_series (
    id          INT          NOT NULL AUTO_INCREMENT,
    series_name VARCHAR(128) NOT NULL,
    description VARCHAR(255)          DEFAULT '',
    PRIMARY KEY (id),
    UNIQUE KEY uq_series_name (series_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
