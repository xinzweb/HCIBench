package com.vm.test;

public class OpenSslWrapperException extends Exception {
	/**
	 * This is thrown whenever the system call to OpenSSL fails
	 * for any reason.
	 */
	private static final long serialVersionUID = 1L;
	public OpenSslWrapperException(String message) {
		super(message);
	}
}