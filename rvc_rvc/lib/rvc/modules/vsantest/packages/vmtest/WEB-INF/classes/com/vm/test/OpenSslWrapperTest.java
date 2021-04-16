package com.vm.test;

import java.io.IOException;

public class OpenSslWrapperTest {

	public static void main(String[] args) {

        String ruby = "/usr/local/rvm/rubies/ruby-2.3.0/bin/ruby";
        String script = "/opt/automation/lib/ossl_wrapper_cli.rb";
        String keyfile = "/opt/automation/conf/key.bin";
        String original = "My cat is named mittens!!1";
        String ciphertext = null;
        String plaintext = null;

        OpenSslWrapper osw = new OpenSslWrapper(ruby, script, keyfile);

        try {
            if (!osw.key_exists()) {
                osw.key_generate();
            }

            ciphertext = osw.encrypt(original);
            plaintext = osw.decrypt(ciphertext);

            System.out.println(original + "\n");
            System.out.println(ciphertext + "\n");
            System.out.println(plaintext + "\n");

        } catch (IOException | OpenSslWrapperException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        } catch (InterruptedException e) {
            // TODO Auto-generated catch block
            e.printStackTrace();
        }
	}
}
