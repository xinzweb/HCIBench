package com.vm.test;

import com.opensymphony.xwork2.ActionSupport;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class Download extends ActionSupport
{
  private static final long serialVersionUID = -7718252218137973708L;
  private String fileName;
  private InputStream inputStream;
  private String tmpName;
  private Map<String, Object> dataMap;

  public String zipfile()
    throws Exception
  {
    this.dataMap = new HashMap<String, Object>();
    File dir = new File("/opt/output/results/");
    List<File> list = new ArrayList<File>();
    File[] files = dir.listFiles();
    for (File file : files) {
    	if (file.isDirectory()){
        list.add(file);
      }
    }
    
    long latest_time=0;
    File result = null;
    
    for (File file : list){
    	if (file.lastModified() > latest_time){
    		latest_time = file.lastModified();
    		result = file;
    	}
    }

  //  Collections.sort(list);
  //  File result = (File)list.get(list.size() - 1);
    this.dataMap.put("name", "/opt/output/results/" + result.getName() + ".zip");
    Zip zip = new Zip("/opt/output/results/" + result.getName(), "/opt/output/results/" + result.getName() + ".zip");
    zip.zip();
    this.dataMap.put("status", "200");
    return "success";
  }

  public String execute() throws Exception
  {
    setFileName(getTmpName().substring(20, getTmpName().length()));
    return "success";
  }

  public String getFileName() {
    return this.fileName;
  }

  public void setFileName(String fileName) {
    this.fileName = fileName;
  }

  public InputStream getInputStream() {
    File file = new File(getTmpName());
    try
    {
      this.inputStream = new FileInputStream(file);
    } catch (FileNotFoundException e) {
      e.printStackTrace();
    }

    if (this.inputStream == null)
    {
      System.out.println("getResource error!");
    }
    return this.inputStream;
  }

  public void setInputStream(InputStream inputStream) {
    this.inputStream = inputStream;
  }

  public Map<String, Object> getDataMap() {
    return this.dataMap;
  }

  public void setDataMap(Map<String, Object> dataMap) {
    this.dataMap = dataMap;
  }

  public String getTmpName() {
    return this.tmpName;
  }

  public void setTmpName(String tmpName) {
    this.tmpName = tmpName;
  }
}