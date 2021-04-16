package com.vm.test;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;

public class Utils
{
  public static String getString(String title)
  {
    Date date = new Date();
    SimpleDateFormat sdf = new SimpleDateFormat("yyyyMMddHHmmss");
    return title + sdf.format(date);
  }

  public static void createDir(String path) {
    File tmp = new File("/opt/tmp");
    if (!tmp.exists()) {
      tmp.mkdir();
    }

    File file = new File(path);
    if (!file.exists())
    	file.mkdirs();
    else
    	file.setLastModified(System.currentTimeMillis());
  }
  
  public static void removeDirectory(File dir) {
	    if (dir.isDirectory()) {
	        File[] files = dir.listFiles();
	        if (files != null && files.length > 0)
	            for (File aFile : files) 
	                removeDirectory(aFile);
	        dir.delete();
	    } 
	    else
	    	dir.delete();
	}
  
  public static void cleanDirectory(String path) {
	  File dir = new File(path);
	  if (dir.isDirectory()) {
		  File[] files = dir.listFiles();
	      if (files != null && files.length > 0)
	          for (File aFile : files) 
	              removeDirectory(aFile);
	    }
	}
}