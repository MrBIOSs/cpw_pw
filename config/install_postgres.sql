CREATE TYPE file_type AS ENUM ('element', 'launcher', 'patcher');

DROP TABLE IF EXISTS files CASCADE;
CREATE TABLE files (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    added INT NOT NULL,
    size BIGINT NOT NULL,
    revision INT NOT NULL,
    md5 CHAR(32) NOT NULL,
    type file_type NOT NULL DEFAULT 'element',
    folder VARCHAR(500) NOT NULL,
    folder_base64 VARCHAR(700) NOT NULL,
    file VARCHAR(255) NOT NULL,
    file_base64 VARCHAR(350) NOT NULL
);

CREATE INDEX idx_files_revision ON files (revision);
CREATE INDEX idx_files_md5 ON files (md5);