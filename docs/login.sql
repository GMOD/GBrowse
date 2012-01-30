DROP DATABASE IF EXISTS gbrowse_login;
CREATE DATABASE gbrowse_login;

GRANT ALL PRIVILEGES 
ON gbrowse_login.* 
TO 'gbrowse'@'localhost' identified by "gbrowse"
WITH GRANT OPTION;

use gbrowse_login;

DROP TABLE IF EXISTS users;
CREATE TABLE users (
    userid            integer not null PRIMARY KEY auto_increment,
    gecos         varchar(64) not null,
    email         varchar(64) not null UNIQUE,
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
    userid            integer not null UNIQUE,
    openid_url   varchar(128)          PRIMARY KEY
) ENGINE=InnoDB;

DROP TABLE IF EXISTS session;
CREATE TABLE session (
    userid            integer not null PRIMARY KEY auto_increment,
    username      varchar(32) not null,
    sessionid        char(32) not null UNIQUE,
    uploadsid        char(32) not null UNIQUE

) ENGINE=InnoDB;
DROP TABLE IF EXISTS favorites; 
CREATE TABLE favorites (
    userid            integer not null PRIMARY KEY auto_increment,
    username      varchar(32) not null, 
    favorite	  varchar(32) not null
)ENGINE=InnoDB;

DROP TABLE IF EXISTS uploads;
CREATE TABLE uploads (
    trackid       varchar(32) not null PRIMARY key,
    userid            integer not null,
    path                text,
    title               text,
    description         text,
    imported          boolean not null,
    creation_date    datetime not null,
    modification_date   datetime,
    sharing_policy      ENUM('private', 'public', 'group', 'casual') not null,
    public_count        int,
    data_source         text
) ENGINE=InnoDB;

DROP TABLE IF EXISTS sharing;
CREATE TABLE sharing (
    trackid       varchar(32) not null,
    userid            integer not null,
    public              boolean
) ENGINE=InnoDB;

DROP TABLE IF EXISTS dbinfo;
CREATE TABLE dbinfo (
    schema_version    int(10) not null UNIQUE
) ENGINE=InnoDB;
