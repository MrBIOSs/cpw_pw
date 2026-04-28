DROP TABLE IF EXISTS `files`;
CREATE TABLE IF NOT EXISTS `files` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `added` INT UNSIGNED NOT NULL,
    `size` BIGINT NOT NULL,
    `revision` INT NOT NULL,
    `md5` CHAR(32) NOT NULL,
    `type` ENUM('element', 'launcher', 'patcher') NOT NULL DEFAULT 'element',
    `folder` VARCHAR(500) NOT NULL,
    `folder_base64` VARCHAR(700) NOT NULL,
    `file` VARCHAR(255) NOT NULL,
    `file_base64` VARCHAR(350) NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_revision` (`revision`),
    INDEX `idx_md5` (`md5`)
) ENGINE=INNODB DEFAULT CHARSET=UTF8MB4;
