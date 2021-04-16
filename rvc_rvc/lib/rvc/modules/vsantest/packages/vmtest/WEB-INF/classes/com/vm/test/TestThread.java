package com.vm.test;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.concurrent.Callable;

public class TestThread
  implements Callable<Boolean>
{
  private String path;

  public TestThread(String path)
  {
    this.path = path;
  }

  public Boolean call()
    throws Exception
  {
    boolean flag = true;
    Process process = null;
    try
    {
      process = Runtime.getRuntime().exec(this.path);
      process.waitFor();

      BufferedReader br = new BufferedReader(new InputStreamReader(
        process.getInputStream()));
      StringBuffer sb = new StringBuffer();
      String line;
      while ((line = br.readLine()) != null)
      {
        sb.append(line).append("\n");
      }
      String result = sb.toString();
      System.out.println(result);
      if (result.indexOf("Script already running") != -1)
        flag = false;
    }
    catch (IOException e)
    {
      e.printStackTrace();
    }
    catch (InterruptedException e) {
      e.printStackTrace();
    }

    return Boolean.valueOf(flag);
  }
}