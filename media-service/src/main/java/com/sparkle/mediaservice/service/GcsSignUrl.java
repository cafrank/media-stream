package com.sparkle.mediaservice.service;

//import org.bouncycastle.util.encoders.Base64;

import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.InvalidKeyException;
import java.security.Key;
import java.security.NoSuchAlgorithmException;
import java.util.*;
import java.util.stream.Collectors;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import static java.util.stream.Collectors.mapping;
import static java.util.stream.Collectors.toList;

/**
 * Samples to create a signed URL for a Cloud CDN endpoint
 */
public class GcsSignUrl {

    // [START signUrl]
    /**
     * Creates a signed URL for a Cloud CDN endpoint with the given key
     * URL must start with http:// or https://, and must contain a forward
     * slash (/) after the hostname.
     *
     * @param url the Cloud CDN endpoint to sign
     * @param key url signing key uploaded to the backend service/bucket, as a 16-byte array
     * @param keyName the name of the signing key added to the back end bucket or service
     * @param expirationTime the date that the signed URL expires
     * @return a properly formatted signed URL
     * @throws InvalidKeyException when there is an error generating the signature for the input key
     * @throws NoSuchAlgorithmException when HmacSHA1 algorithm is not available in the environment
     */
    public static String signUrl(String url,
                                 byte[] key,
                                 String keyName,
                                 Date expirationTime)
            throws InvalidKeyException, NoSuchAlgorithmException {

        final long unixTime = expirationTime.getTime() / 1000;
        String urlToSign = url
                + (url.contains("?") ? "&" : "?")
                + "Expires=" + unixTime
                + "&KeyName=" + keyName;

        String encoded = GcsSignUrl.getSignature(key, urlToSign);
        return urlToSign + "&Signature=" + encoded;
    }

    public static String getSignature(byte[] privateKey, String input)
            throws InvalidKeyException, NoSuchAlgorithmException {
        final String algorithm = "HmacSHA1";        // Do not salt. chkUrl() needs to repeat.
        final int offset = 0;
        Key key = new SecretKeySpec(privateKey, offset, privateKey.length, algorithm);
        Mac mac = Mac.getInstance(algorithm);
        mac.init(key);
        return  Base64.getUrlEncoder().encodeToString(mac.doFinal(input.getBytes()));
    }

    public static Date checkUrlSignature(String url, byte[] key, String keyName)
            throws InvalidKeyException, NoSuchAlgorithmException, UnsupportedEncodingException {

        String [] arr = url.split("&Signature=");
        if (arr.length != 2)    // [urlToSign, encodedSig]
            return null;
        if (!arr[1].equals(GcsSignUrl.getSignature(key, arr[0])))
            return null;
        System.out.println(arr[0]);
        Map<String, List<String>> map = splitParams(arr[0].split("[?]")[1]);

        if (!keyName.equals(map.get("KeyName").get(0))) {
            System.out.println("KeyName mismatch: "+ map.get("KeyName").get(0));
            return null;
        }
        long unixTime = Long.parseLong(map.get("Expires").get(0));
        System.out.println("Expires="+ unixTime);
        return new Date(unixTime * 1000);
    }

    private static Map<String, List<String>> splitParams(String params) throws UnsupportedEncodingException {
        final Map<String, List<String>> query_pairs = new LinkedHashMap<String, List<String>>();
        final String[] pairs = params.split("&");
        for (String pair : pairs) {
            final int idx = pair.indexOf("=");
            final String key = idx > 0 ? URLDecoder.decode(pair.substring(0, idx), "UTF-8") : pair;
            if (!query_pairs.containsKey(key)) {
                query_pairs.put(key, new LinkedList<String>());
            }
            final String value = idx > 0 && pair.length() > idx + 1 ? URLDecoder.decode(pair.substring(idx + 1), "UTF-8") : null;
            query_pairs.get(key).add(value);
        }
        return query_pairs;
    }

    public static void main(String[] args) throws Exception {
        Calendar cal = Calendar.getInstance();
        cal.setTime(new Date());
        cal.add(Calendar.DATE, 1);
        Date tomorrow = cal.getTime();
        String keyName = "MY-KEY-NAME";

        byte[] keyBytes = Base64.getUrlDecoder().decode("dvCuEDg4jJsTXIQgt6CkbA==");
        String result = signUrl("http://example.com/", keyBytes, keyName, tomorrow);
        System.out.println(result);

        Date chkExpire = checkUrlSignature(result, keyBytes, keyName);
        if (chkExpire != null && chkExpire.getTime()/1000 == tomorrow.getTime()/1000) {
            System.out.println("Signature check PASSED");
        } else {
            System.out.println("Signature check FAILED");
        }
    }
}