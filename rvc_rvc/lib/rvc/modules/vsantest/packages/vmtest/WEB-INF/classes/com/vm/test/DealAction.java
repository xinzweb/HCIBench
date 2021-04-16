package com.vm.test;

import com.opensymphony.xwork2.ActionSupport;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.MalformedURLException;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
//import java.util.concurrent.ExecutorService;
//import java.util.concurrent.Executors;
//import java.util.concurrent.Future;

public class DealAction extends ActionSupport {
	private static final long serialVersionUID = 1L;
	private String vcenterIp;
	private String vcenterName;
	private String vcenterPwd;
	private String dcenterName;
	private String clusterName;
	private String rpName;
	private String fdName;
	private String networkName;
	private String staticEnabled;
	private String staticIpprefix;
	private String easyRun;
	private String workloads;
	private String clearCache;
	private String vsanDebug;
	private String reuseVM;
	private String dstoreName;
	private String deployHost;
	private String hosts;
	private String hostName;
	private String hostPwd;
	private String storagePolicy;
	private String vmPrefix;
	private String vmNum;
	private String cpuNum;
	private String ramSize;
	private String diskNum;
	private String diskSize;
	private String filePath;
	private String outPath;
	private String warmUp;
	private String tool;
	private String duration;
	private String cleanUp;
	private String selectVdbench;
	File paramfile;
	private String paramfileFileName;
	File vdbenchfile;
	private String vdbenchfileFileName;
	private Map<String, Object> dataMap;

	public String index() {
		return "success";
	}

	public String generateFile() throws Exception {
		String perf_conf = "/opt/automation/conf/perf-conf.yaml";
		String ossl_conf = "/opt/automation/conf/ossl-conf.yaml";

		this.dataMap = new HashMap<String, Object>();
		File savefile1 = null;
		File file = new File(perf_conf);
		String vc_pass = "";
		String new_vc_pass = "";
		String host_pass = "";
		String new_host_pass = "";
		OpenSslWrapper osw = null;

		String ossl_ruby = getValue(ossl_conf, "ruby");
		String ossl_script = getValue(ossl_conf, "script");
		String ossl_keyfile = getValue(ossl_conf, "keyfile");

		try {
			osw = new OpenSslWrapper(ossl_ruby, ossl_script, ossl_keyfile);
		} catch (Exception e) {;
			e.printStackTrace();
			this.dataMap.put("issue", "Unable to create ossl object: " + ossl_ruby + ":" + ossl_script + ":" + ossl_keyfile + ":" + e.getMessage());
			this.dataMap.put("status", "500");
			return "success";
		}

		try {
			if (!osw.key_exists()) {
				osw.key_generate();
			}
		} catch (Exception e) {;
			e.printStackTrace();
			this.dataMap.put("issue", "Unable to create ossl key: " + ossl_ruby + ":" + ossl_script + ":" + ossl_keyfile + ":" + e.getMessage());
			this.dataMap.put("status", "500");
			return "success";
		}

		// Get VC password field from file
		if (hasValue(perf_conf, "vc_password")) {
			vc_pass = getValue(perf_conf, "vc_password");
		}

		// Get host password field from file
		if (hasValue(perf_conf, "host_password")) {
			host_pass = getValue(perf_conf, "host_password");
		}

		// VC password
		if (getVcenterPwd().length() > 0) {
			// User set a vc password so override any saved passwords
			try {
				String ciphertext = osw.encrypt(getVcenterPwd());
				new_vc_pass = ciphertext;
			} catch (Exception e) {
				e.printStackTrace();
				this.dataMap.put("issue", "Error encrypting data:" + e.getMessage());
				this.dataMap.put("status", "500");
				return "success";
			}
		}

		// Check if the VC password is set or was already saved
		if (vc_pass == "" && new_vc_pass == "")
		{
			this.dataMap.put("issue", "vCenter Password can not be empty!");
			this.dataMap.put("status", "400");
			return "success";
		}

        // Host password
		if (getHostPwd().length() > 0) {
			// User set a host password so override any saved passwords
			try {
				String ciphertext = osw.encrypt(getHostPwd());
				new_host_pass = ciphertext;
			} catch (Exception e) {
				e.printStackTrace();
				this.dataMap.put("issue", "Error encrypting data:" + e.getMessage());
				this.dataMap.put("status", "500");
				return "success";
			}
		}

		if ((host_pass == "") && (new_host_pass == "") && (getClearCache().equals("true") || getVsanDebug().equals("true")))
		{
			this.dataMap.put("issue", "Host Password can not be null!");
			this.dataMap.put("status", "400");
			return "success";
		}

		if (!file.exists()) {
			file.createNewFile();
		}

		if (getParamfile() != null) {

			String path = "/opt/automation/" + getParamPath();
			savefile1 = new File(path + getParamfileFileName());

			copy(this.paramfile, savefile1);
		}

		FileWriter fw = new FileWriter(file);
		BufferedWriter bw = new BufferedWriter(fw);

		StringBuffer data = new StringBuffer();

		if (getVcenterIp().equals(""))
			data.append("vc:  \n");
		else {
			data.append("vc: '" + getVcenterIp().replace("'", "''") + "' \n");
		}
		if (getVcenterName().equals(""))
			data.append("vc_username:  \n");
		else {
			data.append("vc_username: '" + getVcenterName().replace("'", "''") + "' \n");
		}

		if (new_vc_pass.length() > 0) {
			// VC password defined
			data.append("vc_password: '" + new_vc_pass + "' \n");
		}
		else if (vc_pass.length() > 0) {
			// Use stored password
			data.append("vc_password: " + vc_pass + " \n");
		} 
		else {
			// No VC password
			data.append("vc_password:  \n");
		}

		if (getDcenterName().equals(""))
			data.append("datacenter_name: \n");
		else {
			data.append("datacenter_name: '" + getDcenterName().replace("'", "''") + "' \n");
		}
		if (getClusterName().equals(""))
			data.append("cluster_name:  \n");
		else {
			data.append("cluster_name: '" + getClusterName().replace("'", "''") + "' \n");
		}
		if (getRpName().equals(""))
			data.append("resource_pool_name: \n");
		else {
			data.append("resource_pool_name: '" + getRpName().replace("'", "''") + "' \n");
		}
		if (getFdName().equals(""))
			data.append("vm_folder_name: \n");
		else {
			data.append("vm_folder_name: '" + getFdName().replace("'", "''") + "' \n");
		}
		if (getNetworkName().equals(""))
			data.append("network_name: \n");
		else {
			data.append("network_name: '" + getNetworkName().replace("'", "''") + "' \n");
		}

		if (getStaticIpprefix().equals(""))
			data.append("static_ip_prefix: \n");
		else
			data.append("static_ip_prefix: '" + getStaticIpprefix().replace("'", "''") + "' \n");

		data.append("static_enabled: " + getStaticEnabled() + "\n");

		data.append("reuse_vm: " + getReuseVM() + "\n");

		if (getDstoreName().equals(""))
			data.append("datastore_name: \n");
		else {
			String[] datastoreArray = getDstoreName().split("\n");
			data.append("datastore_name: \n");
			for (int i = 0; i < datastoreArray.length; i++) {
				if (!datastoreArray[i].trim().isEmpty())
					data.append("- '" + datastoreArray[i].trim().replace("'", "''") + "' \n");
			}
		}
		data.append("deploy_on_hosts: " + getDeployHost() + "\n");
		if (getHosts().equals("")) {
			data.append("hosts: \n");
		} else {
			String[] hostArray = getHosts().split("\n");
			data.append("hosts: \n");
			for (int i = 0; i < hostArray.length; i++) {
				if (!hostArray[i].trim().isEmpty())
					data.append("- '" + hostArray[i].trim() + "' \n");
			}
		}

		data.append("easy_run: " + getEasyRun() + "\n");
		if (getWorkloads().equals("null")) {
			data.append("workloads: \n");
		} else {
			String[] workloadArray = getWorkloads().split(",");
			data.append("workloads: \n");
			for (int i = 0; i < workloadArray.length; i++) {
				if (!workloadArray[i].trim().isEmpty())
					data.append("- '" + workloadArray[i].trim() + "' \n");
			}
		}

		if (getHostName().equals(""))
			data.append("host_username: \n");
		else {
			data.append("host_username: '" + getHostName().replace("'", "''") + "' \n");
		}

		if (new_host_pass.length() > 0) {
			// host password defined
			data.append("host_password: '" + new_host_pass + "' \n");
		}
		else if (host_pass.length() > 0) {
			// Use stored password
			data.append("host_password: " + host_pass + " \n");
		} 
		else {
			// No host password
			data.append("host_password:  \n");
		}
		
		if (getStoragePolicy().equals(""))
			data.append("storage_policy: \n");
		else {
			data.append("storage_policy: '" + getStoragePolicy().replace("'", "''") + "' \n");
		}
		if (getVmPrefix().equals(""))
			data.append("vm_prefix: \n");
		else {
			data.append("vm_prefix: '" + getVmPrefix().replace("'", "''") + "' \n");
		}
		data.append("clear_cache: " + getClearCache() + "\n");
		data.append("vsan_debug: " + getVsanDebug() + "\n");
		data.append("number_vm: " + getVmNum() + " \n");
		data.append("number_cpu: " + getCpuNum() + " \n");
		data.append("size_ram: " + getRamSize() + " \n");
		data.append("number_data_disk: " + getDiskNum() + " \n");
		data.append("size_data_disk: " + getDiskSize() + " \n");

		String tmpDir = "/opt/tmp/" + Utils.getString("tmp");

		Utils.cleanDirectory("/opt/tmp/");
		if (getEasyRun().equals("false"))
			Utils.createDir(tmpDir);

		// Did not make selection on param files neither have file uploaded
		if (getSelectVdbench().equals("")) // && (getParamfile() == null))
		{
			String path = "/opt/automation/" + getParamPath();
			setFilePath(path);
		}
		// Made selection on param files but not have file uploaded
		else if (getSelectVdbench() != "") // && (getParamfile() == null))
		{
			if (getSelectVdbench().equals("Use All")) {
				String path = "/opt/automation/" + getParamPath();
				setFilePath(path);
			}
			// use single param file from the drop-down list
			// setFilePath(tmpDir);
			else {
				if (getEasyRun().equals("false")) {
					String path = "/opt/automation/" + getParamPath();
					File source = new File(path + getSelectVdbench());
					File dest = new File(tmpDir + "/" + getSelectVdbench());
					copy(source, dest);
					setFilePath(tmpDir);
				}
			}
		}

		if (getFilePath().equals(""))
			data.append("self_defined_param_file_path:  \n");
		else {
			data.append("self_defined_param_file_path: '" + getFilePath() + "' \n");
		}

		if (getOutPath().equals(""))
			setOutPath(Utils.getString("results"));

		data.append("output_path: '" + getOutPath().replace("'", "''") + "' \n");
		data.append("warm_up_disk_before_testing: '" + getWarmUp() + "' \n");
		data.append("tool: '" + getTool() + "' \n");
		data.append("testing_duration: " + getDuration() + " \n");
		data.append("cleanup_vm: " + getCleanUp() + "\n");

		bw.write(data.toString());

		bw.flush();
		bw.close();
		fw.close();

		this.dataMap.put("status", "200");
		return "success";
	}

	// This is the original function call that assumed reading
	// from the perf-conf.yaml and now just a wrapper.
	private String getValue(String keyword){
		return this.getValue("/opt/automation/conf/perf-conf.yaml", keyword);
	}

	// This is the updated function that allows reading from
	// different files.
	private String getValue(String path, String keyword){
		File file = new File(path);
		String value = "";
		if (file.exists())
		{
			BufferedReader reader = null;
			String tempString = null;
			try{
				reader = new BufferedReader(new FileReader(file));
				while ((tempString = reader.readLine()) != null) {
					String cleanString = tempString.trim();
					String key = cleanString.split(":")[0];
					if (key.equals(keyword)){
						int keyWord_length = key.length() + 1;
						if (keyWord_length == cleanString.length())
							return value;
						value = cleanString.substring(keyWord_length, cleanString.length()).trim();		
					}
				}
			}catch (IOException e) {
				e.printStackTrace();
			} finally {
				if (reader != null)
					try {
						reader.close();
					} catch (IOException localIOException2) {
					}
			}
		}
		return value;
	}

	// This is the original function call that assumed reading
	// from the perf-conf.yaml and now just a wrapper.
	private Boolean hasValue(String keyword) {
		return this.hasValue("/opt/automation/conf/perf-conf.yaml", keyword);
	}

	// This is the updated function that allows reading from
	// different files.
	private Boolean hasValue(String path, String keyword){
		File file = new File(path);
		if (file.exists())
		{
			BufferedReader reader = null;
			String tempString = null;
			try{
				reader = new BufferedReader(new FileReader(file));
				while ((tempString = reader.readLine()) != null) {
					String cleanString = tempString.trim();
					String key = cleanString.split(":")[0];
					if (key.equals(keyword)){
						int keyWord_length = key.length() + 1;
						if (keyWord_length == cleanString.length())			
							return false;
						String value = cleanString.substring(keyWord_length, cleanString.length()).trim();	
						if (value != null)
							return true;
						else	
							return false;
						}
				}
			}catch (IOException e) {
				e.printStackTrace();
			} finally {
				if (reader != null)
					try {
						reader.close();
					} catch (IOException localIOException2) {
					}
			}
		}
			return false;
	}
	
	public String readConfigFile() {
		this.dataMap = new HashMap<String, Object>();
		File file = new File("/opt/automation/conf/perf-conf.yaml");

		if (file.exists()) {
			BufferedReader reader = null;
			try {
				reader = new BufferedReader(new FileReader(file));
				String tempString = null;
				String key = null;
				String value = null;
				Boolean inArray = false;

				while ((tempString = reader.readLine()) != null) {
					String cleanString = tempString.trim();
					String last_char = cleanString.substring(cleanString.length() - 1, cleanString.length());
					String first_char = cleanString.substring(0, 1);
					String type = "";
					if (last_char.equals("'")) {
						if (first_char.equals("-"))
							type = "array_value";
						else
							type = "single_str";
					} else {
						if (last_char.equals(":"))
							type = "array_key";
						else
							type = "single";
					}
					if (type.equals("single_str") || type.equals("single") || type.equals("array_key")) {
						int t = cleanString.indexOf(":");

						if (t != -1) {
							inArray = false;
							key = cleanString.substring(0, t);
							if (key.equals("vc_password") || key.equals("host_password"))
								continue;
							int single_quote_index = cleanString.indexOf("'");
							if (type.equals("single_str"))
								value = cleanString.substring(single_quote_index + 1, cleanString.length() - 1);
							else if (type.equals("single"))
								value = cleanString.substring(t + 1, cleanString.length()).trim();
							else
								value = "";
						} else {
							System.err.println("YAML invalid");
						}
					} else {
						int t = cleanString.indexOf("'");
						if (!inArray) {
							inArray = true;
							value = cleanString.substring(t + 1, cleanString.length() - 1) + "\n";
						} else
							value = value + cleanString.substring(t + 1, cleanString.length() - 1) + "\n";
					}
					this.dataMap.put(key, value);
				}
				reader.close();
			} catch (IOException e) {
				e.printStackTrace();

				if (reader != null)
					try {
						reader.close();
					} catch (IOException localIOException1) {
					}
			} finally {
				if (reader != null)
					try {
						reader.close();
					} catch (IOException localIOException2) {
					}
			}
		}
		return "success";
	}
	
	

	public String runTest() throws Exception {
		this.dataMap = new HashMap<String, Object>();
		Process process = null;
		String command = "/opt/automation/start-testing.sh";
		try {
			process = Runtime.getRuntime().exec(command);
			process.waitFor();

			BufferedReader br = new BufferedReader(new InputStreamReader(process.getInputStream()));
			StringBuffer sb = new StringBuffer();
			String line;
			while ((line = br.readLine()) != null) {
				sb.append(line).append("\n");
			}
		} catch (IOException e) {
			e.printStackTrace();
		} catch (InterruptedException e) {
			e.printStackTrace();
		} finally {
			System.out.println("Test is runing");
		}

		this.dataMap.put("status", "200");
		return "success";
	}

	public String isTestFinished() throws Exception {
		this.dataMap = new HashMap<String, Object>();
		// ExecutorService pool = Executors.newFixedThreadPool(1);
		String path = "/opt/automation/is-test-finished.sh";

		Callable<?> c1 = new TestThread(path);
		// Future<?> f1 = pool.submit(c1);
		// Boolean result = (Boolean) f1.get();

		Boolean result = (Boolean) c1.call();
		System.out.println(result);
		if (result.booleanValue())
			this.dataMap.put("data", "200");
		else {
			this.dataMap.put("data", "404");
		}
		return "success";
	}
	
	public String cleanupVms() throws Exception {
		this.dataMap = new HashMap<String, Object>();
		Process process = null;
		String command = "/opt/automation/cleanup-vm.sh";
		StringBuffer sb = new StringBuffer();
		int deletedVM = 0;
		String removeLog = "";
		try {
			process = Runtime.getRuntime().exec(command.toString());
      		process.waitFor();
      		BufferedReader br = new BufferedReader(new InputStreamReader(process.getInputStream()));
      		String line;
      		while ((line = br.readLine()) != null)
      		{
        		sb.append(line);
        		if (line.contains("Destroy") && line.endsWith("success")){
        			removeLog = removeLog + line;
        			deletedVM ++;
        		}
      		}
    	} 
    	catch (IOException e){
      		e.printStackTrace();
    	} 
    	catch (InterruptedException e){
      		e.printStackTrace();
    	} 
    	finally {
			System.out.println(removeLog);
		}
		String vmPref = getValue("vm_prefix");
		if (deletedVM != 0){
			String succMsg = "VMs with prefix: " + vmPref + " are deleted ";
			this.dataMap.put("status", "200");
			this.dataMap.put("content", succMsg);
		}	
		else
		{
			this.dataMap.put("status", "500");
			this.dataMap.put("issue", "Unable to find guest VMs with prefix: " + vmPref);
		}
		return "success";
			
	}

	public String killTest() throws InterruptedException, ExecutionException {
		this.dataMap = new HashMap<String, Object>();
		Process process = null;
		String command = "/opt/automation/kill-all-in-one-testing.sh";
		try {
			process = Runtime.getRuntime().exec(command);
			process.waitFor();

			BufferedReader br = new BufferedReader(new InputStreamReader(process.getInputStream()));
			StringBuffer sb = new StringBuffer();
			String line;
			while ((line = br.readLine()) != null) {
				sb.append(line).append("\n");
			}
		} catch (IOException e) {
			e.printStackTrace();
		} catch (InterruptedException e) {
			e.printStackTrace();
		} finally {
			System.out.println("Test is killed");
		}

		this.dataMap.put("status", "200");
		return "success";
	}

	public String validateFile() throws Exception {
		this.dataMap = new HashMap<String, Object>();
		try {
			Process process = Runtime.getRuntime().exec("/opt/automation/pre-validate-config.sh");
			process.waitFor();
			final InputStream in = process.getInputStream();
			final InputStream err = process.getErrorStream();

			BufferedReader br = new BufferedReader(new InputStreamReader(in, "UTF-8"));
			BufferedReader error = new BufferedReader(new InputStreamReader(err, "UTF-8"));

			StringBuffer sb = new StringBuffer();
			String line;

			while ((line = br.readLine()) != null) {
				System.out.println(line + "...");
				sb.append(line).append("\n");
			}

			while ((line = error.readLine()) != null) {
				System.out.println(line);
				sb.append(line).append("\n");
			}
			this.dataMap.put("data", sb.toString());
			if (br != null)
				br.close();
			if (error != null)
				error.close();
		} catch (Throwable e) {
			System.out.println("call shell failed. " + e);
		}
		return "success";
	}

	public String readLog() throws Exception {
		this.dataMap = new HashMap<String, Object>();

		File file = new File("/opt/automation/logs/test-status.log");
		BufferedReader reader = null;
		if (file.exists()) {
			try {
				reader = new BufferedReader(new FileReader(file));
				String tempString = null;
				StringBuffer sb = new StringBuffer();
				while ((tempString = reader.readLine()) != null) {
					sb.append(tempString + "<br>");
				}

				sb.append("...<br>");
				this.dataMap.put("data", sb.toString());
				reader.close();
			} catch (IOException e) {
				e.printStackTrace();

				if (reader != null)
					try {
						reader.close();
					} catch (IOException localIOException1) {
					}
			} finally {
				if (reader != null)
					try {
						reader.close();
					} catch (IOException localIOException2) {
					}
			}
		}
		// else
		// return "not exist";
		return "success";
	}

	public String uploadParamfile() throws IOException, InterruptedException {
		this.dataMap = new HashMap<String, Object>();
		System.out.println(getParamfileFileName());
		System.out.println(getParamPath());
		if (getParamfileFileName() != null) {
			String path = "/opt/automation/" + getParamPath();
			File savefile3 = new File(path + getParamfileFileName());
			copy(this.paramfile, savefile3);
		}
		this.dataMap.put("status", "200");
		return "success";
	}

	public String uploadVdbench() throws IOException, InterruptedException {
		this.dataMap = new HashMap<String, Object>();

		File dir = new File("/opt/output/vdbench-source");
		if (dir.isDirectory()) {
			File[] children = dir.listFiles();
			for (int i = 0; i < children.length; i++) {
				children[i].delete();
			}
		}
		System.out.println(getVdbenchfileFileName());
		if (getVdbenchfileFileName() != null) {
			File savefile2 = new File("/opt/output/vdbench-source/" + getVdbenchfileFileName());

			copy(this.vdbenchfile, savefile2);
		}
		this.dataMap.put("status", "200");
		return "success";
	}

	private void copy(File src, File dst) {
		try {
			int byteread = 0;
			InputStream in = null;
			FileOutputStream out = null;
			try {
				in = new FileInputStream(src);
				out = new FileOutputStream(dst);
				byte[] buffer = new byte[1444];
				while ((byteread = in.read(buffer)) != -1) {
					out.write(buffer, 0, byteread);
				}
			} finally {
				if (in != null) {
					in.close();
				}
				if (out != null)
					out.close();
			}
		} catch (Exception e) {
			e.printStackTrace();
		}
	}

	public String hasVdbenchFile() {
		this.dataMap = new HashMap<String, Object>();
		File dir = new File("/opt/output/vdbench-source/");

		if (dir.isDirectory()) {
			if (dir.listFiles().length > 0)
				this.dataMap.put("data", "200");
			else {
				this.dataMap.put("data", "404");
			}
		}

		return "success";
	}

	public String getVdbenchParamFile() {
		this.dataMap = new HashMap<String, Object>();
		String path = "/opt/automation/" + getParamPath();
		File dir = new File(path);

		if (dir.isDirectory()) {
			if (dir.listFiles().length > 0) {
				String[] files = dir.list();
				Arrays.sort(files);
				this.dataMap.put("data", files);
			} else {
				this.dataMap.put("data", "404");
			}
		}
		return "success";
	}

	public String getVcenterIp() {
		return this.vcenterIp == null ? "" : this.vcenterIp;
	}

	public void setVcenterIp(String vcenterIp) {
		this.vcenterIp = vcenterIp;
	}

	public String getVcenterName() {
		return this.vcenterName == null ? "" : this.vcenterName;
	}

	public void setVcenterName(String vcenterName) {
		this.vcenterName = vcenterName;
	}

	public String getVcenterPwd() {
		return this.vcenterPwd == null ? "" : this.vcenterPwd;
	}

	public void setVcenterPwd(String vcenterPwd) {
		this.vcenterPwd = vcenterPwd;
	}

	public Map<String, Object> getDataMap() {
		return this.dataMap;
	}

	public void setDataMap(Map<String, Object> dataMap) {
		this.dataMap = dataMap;
	}

	public String getDcenterName() {
		return this.dcenterName == null ? "" : this.dcenterName;
	}

	public void setDcenterName(String dcenterName) {
		this.dcenterName = dcenterName;
	}

	public String getClusterName() {
		return this.clusterName == null ? "" : this.clusterName;
	}

	public void setClusterName(String clusterName) {
		this.clusterName = clusterName;
	}

	public String getRpName() {
		return this.rpName == null ? "" : this.rpName;
	}

	public void setRpName(String rpName) {
		this.rpName = rpName;
	}

	public String getFdName() {
		return this.fdName == null ? "" : this.fdName;
	}

	public void setFdName(String fdName) {
		this.fdName = fdName;
	}

	public String getNetworkName() {
		return this.networkName == null ? "" : this.networkName;
	}

	public void setNetworkName(String networkName) {
		this.networkName = networkName;
	}

	public String getStaticIpprefix() {
		return this.staticIpprefix == null ? "" : this.staticIpprefix;
	}

	public void setStaticIpprefix(String staticIpprefix) {
		this.staticIpprefix = staticIpprefix;
	}

	public String getDstoreName() {
		return this.dstoreName == null ? "" : this.dstoreName;
	}

	public void setDstoreName(String dstoreName) {
		this.dstoreName = dstoreName;
	}

	public String getDeployHost() {
		return this.deployHost;
	}

	public void setDeployHost(String deployHost) {
		this.deployHost = deployHost;
	}

	public String getHosts() {
		return this.hosts == null ? "" : this.hosts;
	}

	public void setHosts(String hosts) {
		this.hosts = hosts;
	}

	public String getWorkloads() {
		return this.workloads == null ? "" : this.workloads;
	}

	public void setWorkloads(String workloads) {
		this.workloads = workloads;
	}

	public String getHostName() {
		return this.hostName == null ? "" : this.hostName;
	}

	public void setHostName(String hostName) {
		this.hostName = hostName;
	}

	public String getHostPwd() {
		return this.hostPwd == null ? "" : this.hostPwd;
	}

	public void setHostPwd(String hostPwd) {
		this.hostPwd = hostPwd;
	}

	public String getStoragePolicy() {
		return this.storagePolicy == null ? "" : this.storagePolicy;
	}

	public void setStoragePolicy(String storagePolicy) {
		this.storagePolicy = storagePolicy;
	}

	public String getVmPrefix() {
		return this.vmPrefix == null ? "" : this.vmPrefix;
	}

	public void setVmPrefix(String vmPrefix) {
		this.vmPrefix = vmPrefix;
	}

	public String getVmNum() {
		return this.vmNum == null ? "0" : this.vmNum;
	}

	public void setVmNum(String vmNum) {
		this.vmNum = vmNum;
	}
	
	public String getCpuNum() {
		return this.cpuNum == null ? "0" : this.cpuNum;
	}

	public void setCpuNum(String cpuNum) {
		this.cpuNum = cpuNum;
	}
	
	public String getRamSize() {
		return this.ramSize == null ? "0" : this.ramSize;
	}

	public void setRamSize(String ramSize) {
		this.ramSize = ramSize;
	}

	public String getDiskNum() {
		return this.diskNum == null ? "0" : this.diskNum;
	}

	public void setDiskNum(String diskNum) {
		this.diskNum = diskNum;
	}

	public String getDiskSize() {
		return this.diskSize == null ? "0" : this.diskSize;
	}

	public void setDiskSize(String diskSize) {
		this.diskSize = diskSize;
	}

	public String getFilePath() {
		return this.filePath == null ? "" : this.filePath;
	}

	public void setFilePath(String filePath) {
		this.filePath = filePath;
	}

	public String getOutPath() {
		return this.outPath == null ? "" : this.outPath;
	}

	public void setOutPath(String outPath) {
		this.outPath = outPath;
	}

	public String getWarmUp() {
		return this.warmUp;
	}

	public void setWarmUp(String warmUp) {
		this.warmUp = warmUp;
	}

	public String getTool() {
		return this.tool;
	}

	public void setTool(String tool) {
		this.tool = tool;
	}

	public String getParamPath() {
		return getTool() + "-param-files/";
	}

	public String getDuration() {
		return this.duration == null ? "0" : this.duration;
	}

	public void setDuration(String duration) {
		this.duration = duration;
	}

	public String getCleanUp() {
		return this.cleanUp;
	}

	public void setCleanUp(String cleanUp) {
		this.cleanUp = cleanUp;
	}

	public String getStaticEnabled() {
		return this.staticEnabled;
	}

	public void setStaticEnabled(String staticEnabled) {
		this.staticEnabled = staticEnabled;
	}

	public String getEasyRun() {
		return this.easyRun;
	}

	public void setEasyRun(String easyRun) {
		this.easyRun = easyRun;
	}

	public String getClearCache() {
		return this.clearCache;
	}

	public void setClearCache(String clearCache) {
		this.clearCache = clearCache;
	}
	
	public String getVsanDebug() {
		return this.vsanDebug;
	}

	public void setVsanDebug(String vsanDebug) {
		this.vsanDebug = vsanDebug;
	}

	public String getReuseVM() {
		return this.reuseVM;
	}

	public void setReuseVM(String reuseVM) {
		this.reuseVM = reuseVM;
	}

	public File getParamfile() {
		return this.paramfile;
	}

	public void setParamfile(File paramfile) {
		this.paramfile = paramfile;
	}

	public String getParamfileFileName() {
		return this.paramfileFileName;
	}

	public void setParamfileFileName(String paramfileFileName) {
		this.paramfileFileName = paramfileFileName;
	}

	public File getVdbenchfile() {
		return this.vdbenchfile;
	}

	public void setVdbenchfile(File vdbenchfile) {
		this.vdbenchfile = vdbenchfile;
	}

	public String getVdbenchfileFileName() {
		return this.vdbenchfileFileName;
	}

	public void setVdbenchfileFileName(String vdbenchfileFileName) {
		this.vdbenchfileFileName = vdbenchfileFileName;
	}

	public String getSelectVdbench() {
		return this.selectVdbench;
	}

	public void setSelectVdbench(String selectVdbench) {
		this.selectVdbench = selectVdbench;
	}
}
