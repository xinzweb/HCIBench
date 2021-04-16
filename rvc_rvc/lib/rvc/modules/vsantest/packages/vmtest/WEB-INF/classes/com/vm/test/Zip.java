package com.vm.test;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public class Zip
{
  private String path;
  private String name;
  static final int BUFFER = 2048;

  public Zip(String path, String name)
  {
    this.path = path;
    this.name = name;
  }

  public void zipFile2() {
    try {
      BufferedInputStream origin = null;
      FileOutputStream dest = new FileOutputStream(this.name);
      ZipOutputStream out = new ZipOutputStream(new BufferedOutputStream(
        dest));
      byte[] data = new byte[2048];
      File f = new File(this.path);
      File[] files = f.listFiles();

      for (int i = 0; i < files.length; i++) {
        FileInputStream fi = new FileInputStream(files[i]);
        origin = new BufferedInputStream(fi, 2048);
        ZipEntry entry = new ZipEntry(files[i].getName());
        out.putNextEntry(entry);
        int count;
        while ((count = origin.read(data, 0, 2048)) != -1)
        {
          out.write(data, 0, count);
        }
        origin.close();
      }
      out.close();
    } catch (Exception e) {
      e.printStackTrace();
    }
  }

  public void zip()
  {
    try {
      OutputStream os = new FileOutputStream(this.name);
      BufferedOutputStream bos = new BufferedOutputStream(os);
      ZipOutputStream zos = new ZipOutputStream(bos);
      File file = new File(this.path);
      String basePath = null;
      if (file.isDirectory())
        basePath = file.getPath();
      else {
        basePath = file.getParent();
      }
      zipFile(file, basePath, zos);
      zos.closeEntry();
      zos.close();
    }
    catch (Exception e) {
      e.printStackTrace();
    }
  }

  private void zipFile(File source, String basePath, ZipOutputStream zos) {
    File[] files = new File[0];
    if (source.isDirectory()) {
      files = source.listFiles();
    } else {
      files = new File[1];
      files[0] = source;
    }

    byte[] buf = new byte[1024];
    int length = 0;
    try {
      for (File file : files)
        if (file.isDirectory()) {
          String pathName = file.getPath().substring(basePath.length() + 1) + 
            "/";
          zos.putNextEntry(new ZipEntry(pathName));
          zipFile(file, basePath, zos);
        } else {
          String pathName = file.getPath().substring(basePath.length() + 1);
          InputStream is = new FileInputStream(file);
          BufferedInputStream bis = new BufferedInputStream(is);
          zos.putNextEntry(new ZipEntry(pathName));
          while ((length = bis.read(buf)) > 0) {
            zos.write(buf, 0, length);
          }
          is.close();
        }
    }
    catch (Exception e)
    {
      e.printStackTrace();
    }
  }
}