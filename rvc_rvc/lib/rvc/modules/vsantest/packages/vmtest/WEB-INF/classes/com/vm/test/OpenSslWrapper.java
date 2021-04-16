package com.vm.test;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;

import org.apache.commons.io.FileUtils;


public class OpenSslWrapper {
	private File ruby;
	private File script;
	private File keyfile;

	private String exec_wrapper(String[] command) throws IOException, OpenSslWrapperException, InterruptedException {
		String line = null;
		String stdout = "";
		String stderr = "";
                  
        Process process = Runtime.getRuntime().exec(command);
        
        process.waitFor();
        
        BufferedReader stdInput = new BufferedReader(new InputStreamReader(process.getInputStream()));
        BufferedReader stdError = new BufferedReader(new InputStreamReader(process.getErrorStream()));
        
        // read the output from the command
        if (process.exitValue() != 0) {
        	while ((line = stdError.readLine()) != null) {
        		stderr += line;
	            }
        	throw new OpenSslWrapperException(stderr);
        }
        else {
        	 while ((line = stdInput.readLine()) != null) {
        		 stdout += line;
	            }
        	 return stdout;
        }	
	}
	
	public OpenSslWrapper(String ruby, String script, String keyfile) {
		this.ruby = new File(ruby);
		this.script = new File(script);
		this.keyfile = new File(keyfile);
		
		if (!this.ruby.exists()) {
			throw new IllegalArgumentException("Ruby path is not valid");
		}
	
		if (!this.script.exists()) {
			throw new IllegalArgumentException("Script path is not valid");
		}
	}
	
	public boolean key_exists() throws IOException, OpenSslWrapperException, InterruptedException {
		String[] command = new String[] {
				this.ruby.toString(),
				this.script.toString(),
        		"--key-exists",
				"-k",
				this.keyfile.toString()
        };
        return (this.exec_wrapper(command).equals("true"));
	}
	
	public boolean key_delete() throws IOException, OpenSslWrapperException, InterruptedException {
		String[] command = new String[] {
				this.ruby.toString(),
				this.script.toString(),
        		"--key-delete",
				"-k",
				this.keyfile.toString()
        };
		return (this.exec_wrapper(command).equals("true"));
	}
	
	public String key_generate() throws IOException, OpenSslWrapperException, InterruptedException {
        String[] command = new String[] {
				this.ruby.toString(),
				this.script.toString(),
        		"--key-generate",
				"-k",
				this.keyfile.toString()
        };      
        return this.exec_wrapper(command);
	}
	
	public String encrypt(String plaintext) throws IOException, OpenSslWrapperException, InterruptedException {
        String[] command = new String[] {
				this.ruby.toString(),
				this.script.toString(),
        		"-e",
        		plaintext,
				"-k",
				this.keyfile.toString()
        };   
        return this.exec_wrapper(command);
	}
	
	public String decrypt(String ciphertext) throws IOException, OpenSslWrapperException, InterruptedException {
		
        String[] command = new String[] {
				this.ruby.toString(),
				this.script.toString(),
        		"-d",
        		ciphertext,
				"-k",
				this.keyfile.toString()
        };     
        return this.exec_wrapper(command);
	}
}
