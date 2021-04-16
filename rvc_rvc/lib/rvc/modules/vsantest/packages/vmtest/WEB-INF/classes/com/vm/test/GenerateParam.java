package com.vm.test;

import com.opensymphony.xwork2.ActionSupport;
import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.HashMap;
import java.util.Map;

public class GenerateParam extends ActionSupport
{
	private static final long serialVersionUID = 1L;
	private int diskNum;
	private int workSet;
	private int threadNum;
	private String blockSize;
	private int readPercent;
	private int randomPercent;
	private int ioRate;
	private int testTime;
	private int warmupTime;
	private int intervalTime;
	private int cpuUsage;
	private String name;
	private Map<String, Object> dataMap;
	private String tool;

	public String toPage()
			throws Exception
	{
		this.dataMap = new HashMap<String, Object>();

		return "success";
	}

	public String deleteFile() throws Exception {
		this.dataMap = new HashMap<String, Object>();
		if (getName() != null) {
			String parampath = "/opt/automation/" + getTool() + "-param-files/";
			System.out.println(parampath);
			File file = new File(parampath + this.name);
			if (file.exists()) {
				file.delete();
				this.dataMap.put("status", "200");
			}
		}
		return "success";
	}

	public String generateParamFile() throws Exception {
		this.dataMap = new HashMap<String, Object>();
		Process process = null;
		StringBuffer sb = new StringBuffer();
		StringBuffer command = new StringBuffer();
		String toolParam = getTool();
		if (toolParam.equals("vdbench"))
			command.append("/opt/automation/generate-vdb-param-file.sh -n " + getDiskNum());
		if (toolParam.equals("fio"))
			command.append("fioconfig create -d /opt/automation/fio-param-files -n " + getDiskNum());
		command.append(" -w " + getWorkSet());
		command.append(" -b " + getBlockSize());
		command.append(" -r " + getReadPercent());
		command.append(" -s " + getRandomPercent());
		command.append(" -e " + getTestTime());

		if (getThreadNum() != 0) {
			command.append(" -t " + getThreadNum());
		}

		if (getIoRate() != 0){
			if (toolParam.equals("fio")){
				int rdpct = getReadPercent();
				int rwmix = 2;
				if (rdpct == 0 || rdpct == 100)
					rwmix = 1;
				
				// charlesl
				// If we are going to get a double then cast to int, they not cast  to integer right away?
				int iorate = (int)((double)getIoRate()/(getDiskNum()*rwmix));
			
				// charlesl
				// Since iorate must be non zero but we are doing some fancy math with the numbers of disks 
				// and getting a double, this can end up being zero and causing an error. In this case we
				// set iorate to 1 which is the minimum value.
				if (iorate < 1)
					iorate = 1;
				command.append(" -o " + (int)iorate);
			}
			else
				command.append(" -o " + getIoRate());
		}

		if (getWarmupTime() != 0) {
			command.append(" -m " + getWarmupTime());
		}

		if (getIntervalTime() != 0) {
			command.append(" -i " + getIntervalTime());
		}

		if (getCpuUsage() != 0) {
			if (toolParam.equals("fio")){
				command.append(" -nc 4 -c " + getCpuUsage());
			}
		}

		System.out.println(command.toString());
		try {
			process = Runtime.getRuntime().exec(command.toString());
			process.waitFor();
			BufferedReader br = new BufferedReader(new InputStreamReader(
					process.getInputStream()));
			String line;
			while ((line = br.readLine()) != null)
			{
				sb.append(line);
			}
		} catch (IOException e) {
			e.printStackTrace();
		} catch (InterruptedException e) {
			e.printStackTrace();
		} finally {
			System.out.println(sb.toString());
			if (sb.toString().indexOf("good") != -1 || sb.toString().indexOf("Output file:") != -1){
				this.dataMap.put("status", "200");}
			else
				this.dataMap.put("status", "404");
		}
		return "success";
	}

	public int getDiskNum() {
		return this.diskNum;
	}

	public void setDiskNum(int diskNum) {
		this.diskNum = diskNum;
	}

	public String getTool() {
		return this.tool;
	}

	public void setTool(String tool) {
		this.tool = tool;
	}

	public int getThreadNum() {
		return this.threadNum;
	}

	public void setThreadNum(String threadNum) {
		if (!threadNum.isEmpty())
			this.threadNum = Integer.parseInt(threadNum);
	}

	public String getBlockSize() {
		return this.blockSize;
	}

	public void setBlockSize(String blockSize) {
		this.blockSize = blockSize;
	}

	public int getReadPercent() {
		return this.readPercent;
	}

	public void setReadPercent(int readPercent) {
		this.readPercent = readPercent;
	}

	public int getRandomPercent() {
		return this.randomPercent;
	}

	public void setRandomPercent(int randomPercent) {
		this.randomPercent = randomPercent;
	}

	public int getIoRate() {
		return ioRate;
	}

	public void setIoRate(String ioRate) {
		if(!ioRate.isEmpty())
			this.ioRate = Integer.parseInt(ioRate);
	}

	public int getCpuUsage() {
		return this.cpuUsage;
	}

	public void setCpuUsage(String cpuUsage) {
		if(!cpuUsage.isEmpty())
			this.cpuUsage = Integer.parseInt(cpuUsage);
	}

	public int getTestTime() {
		return this.testTime;
	}

	public void setTestTime(int testTime) {
		this.testTime = testTime;
	}

	public int getWarmupTime() {
		return this.warmupTime;
	}

	public void setWarmupTime(String warmupTime) {
		if(!warmupTime.isEmpty())
			this.warmupTime = Integer.parseInt(warmupTime);
	}

	public int getIntervalTime() {
		return this.intervalTime;
	}

	public void setIntervalTime(String intervalTime) {
		if (!intervalTime.isEmpty())
			this.intervalTime = Integer.parseInt(intervalTime);
	}

	public int getWorkSet() {
		return this.workSet;
	}

	public void setWorkSet(int workSet) {
		this.workSet = workSet;
	}

	public Map<String, Object> getDataMap() {
		return this.dataMap;
	}

	public void setDataMap(Map<String, Object> dataMap) {
		this.dataMap = dataMap;
	}

	public String getName() {
		return this.name;
	}

	public void setName(String name) {
		this.name = name;
	}
}