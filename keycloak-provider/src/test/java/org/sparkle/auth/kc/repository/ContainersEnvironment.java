package org.sparkle.auth.kc.repository;

import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;

public class ContainersEnvironment {
    @Container
    public static MySQLContainer mySQLContainer = MySqlTestContainer.getInstnce();
}
