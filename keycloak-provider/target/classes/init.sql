CREATE TABLE t_user (
    id INTEGER NOT NULL AUTO_INCREMENT,
    username varchar(50),
    password varchar(50),
    email varchar(80),
    firstName varchar(50),
    lastName varchar(50),
    PRIMARY KEY (id)
);

CREATE TABLE vms_customer (
    cust_id INTEGER NOT NULL AUTO_INCREMENT,
    login varchar(50),
    password varchar(50),
    email varchar(80),
    phone varchar(80),
    firstName varchar(50),
    lastName varchar(50),
    PRIMARY KEY (cust_id)
);

CREATE TABLE vms_cust_attr (
    id INTEGER NOT NULL AUTO_INCREMENT,
    cust_id INTEGER,
    mkey varchar(50),
    mvalue varchar(80),
    PRIMARY KEY (id)
);
