DROP DATABASE IF EXISTS gbrowse_login;
CREATE DATABASE gbrowse_login;

GRANT ALL PRIVILEGES 
ON gbrowse_login.* 
TO 'gbrowse'@'localhost' identified by "gbrowse"
WITH GRANT OPTION;

use gbrowse_login;

DROP TABLE IF EXISTS users;
CREATE TABLE users (
    userid        varchar(32) not null UNIQUE key,
    username      varchar(32) not null PRIMARY key,
    email         varchar(64) not null UNIQUE key,
    pass          varchar(32) not null,
    remember          boolean not null,
    openid_only       boolean not null,
    confirmed         boolean not null,
    cnfrm_code    varchar(32) not null,
    last_login      timestamp not null,
    created          datetime not null
) ENGINE=InnoDB;

DROP TABLE IF EXISTS openid_users;
CREATE TABLE openid_users (
    userid        varchar(32) not null,
    username      varchar(32) not null,
    openid_url   varchar(128) not null PRIMARY key
) ENGINE=InnoDB;


