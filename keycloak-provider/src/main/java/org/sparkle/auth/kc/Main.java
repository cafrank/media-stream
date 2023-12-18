package org.sparkle.auth.kc;

import org.sparkle.auth.kc.repository.UserMy12Repository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;

@SpringBootApplication
@ComponentScan("org.sparkle.auth.kc")

public class  Main {

    @Autowired
    private UserMy12Repository myRepo;

    public static void main(String[] args) {
        SpringApplication.run(Main.class, args);
    }

    @Bean
    public CommandLineRunner initUsers() {
        return (args) -> { };
    }
}