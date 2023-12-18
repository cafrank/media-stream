package org.sparkle.auth.kc.repository;

import org.testcontainers.containers.MySQLContainer;

// https://www.youtube.com/watch?v=VfwP3GOridU
public class MySqlTestContainer extends MySQLContainer<MySqlTestContainer> {
    public static final String IMAGE_VERSION = "mysql:8.2.0";
    public static final String DATABASE_NAME = "mysql:8.2.0";
    public static MySQLContainer container;
    public MySqlTestContainer() {
        super(IMAGE_VERSION);
    }

    public static MySQLContainer getInstnce() {
        if (container == null) {
            container = new MySqlTestContainer()
                    .withDatabaseName(DATABASE_NAME)
                    .withInitScript("init.sql");    // CREATE TABLE t_user()
        }
        return container;
    }

    @Override
    public void start() {
        super.start();
        System.setProperty("AUTH_DB_URL", container.getJdbcUrl());
        System.setProperty("AUTH_DB_USER", container.getUsername());
        System.setProperty("AUTH_DB_PASSWORD", container.getPassword());
    }

    @Override
    public void stop() {
    }
}
