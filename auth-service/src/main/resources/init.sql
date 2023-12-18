CREATE TABLE t_user (
    id INTEGER NOT NULL AUTO_INCREMENT,
    username varchar(50),
    password varchar(50),
    email varchar(80),
    firstName varchar(50),
    lastName varchar(50),
    PRIMARY KEY (id)
);