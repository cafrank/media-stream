package org.sparkle.auth.kc.modle;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import javax.persistence.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@AllArgsConstructor
@NoArgsConstructor
@Builder
@Data
@Entity
@Table(name = "vms_customer")
public class UserMy12 {
    @Id
    @Column(name = "cust_id")
//    @GeneratedValue(strategy = GenerationType.AUTO)
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String firstName;
    private String lastName;
    private String login;
    private String email;
    private String phone;
    @OneToMany(cascade = CascadeType.ALL,
            orphanRemoval = true
    )
    @JoinColumn(name = "cust_id")
    private List<UserAttr> attrList = new ArrayList<>();
}