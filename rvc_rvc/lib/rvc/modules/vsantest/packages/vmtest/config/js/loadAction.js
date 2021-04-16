$(document).ready(
		function() {
			var time;
			var path = "https://" + window.location.host + "/VMtest/hasvdbenchfile";
			var path2 = "https://" + window.location.host + "/VMtest/getvdbenchparamFile";
			var path3 = "https://" + window.location.host + "/VMtest/readconfigfile";
			var p1 = 0;
			var p2 = 40;
			var p3 = 60;
			var p4 = 90;
			var p5 = 100;

			time = setInterval("begincheck()", 1000);

			function getSelectList() {
				var formdata = new FormData();
				var toolParam = document.getElementById("tool").value;
				var vmPrefix = document.getElementById("vmPrefix").value;

				// change vm name prefix
				if (['hci-fio','hci-vdb',''].indexOf(vmPrefix.trim()) != -1) {
					if (toolParam == "fio")
						document.getElementById("vmPrefix").value = "hci-fio";
					if (toolParam == "vdbench")
						document.getElementById("vmPrefix").value = "hci-vdb";
				}
				$("#selectparam").empty();
				var select = $("#selectparam");
				formdata.append("tool", toolParam);
				$.ajax({
					type : "post",
					contentType : false,
					processData : false,
					data : formdata,
					url : path2,
					async : true,
					success : function(data) {
						if (data["data"] != "404") {
							var mm = data["data"];
							$.each(mm, function(index, array) {
								select.append("<option value='Value'>" + array + "</option>");
							});
							select.append("<option value='All'>Use All</option>");
						}
					}
				});
			}
			;

			showModel = function(data) {
				$('#myModal').modal('show');
				$("#pcontent").text(data);
				$("#progress").hide();
			};
			showInfoModel = function(data) {
				var msg = data.replace(/\n/g, "<br />");
				$("#info-content").html(msg);
			};
			istestfinish = function() {
				var url = "https://" + window.location.host + "/VMtest/istestfinish";
				$.getJSON(url, function(data) {
					if (data["data"] != "200") {
						showModel("Test is finished");
						$("#cancelprocess").hide();
						clearInterval(time);
						// $("#runTest").removeAttr("disabled");
					} else {
						//$('#myModal').modal('show');
						//$("#progress").show();
						var mypath = "https://" + window.location.host + "/VMtest/readlog";
						$.getJSON(mypath, function(data2) {
							var str = data2["data"];
							$("#pcontent").html(str);
							if (str.indexOf("Testing Finished") == 0) {
								$("#progressbar").css("width", "100%");
							} else if (str.indexOf("I/O Test Finished") != -1) {
								p4 = p4 + 1;
								if (p3 < 98) {
									$("#progressbar").css("width", p4 + "%");
								} else {
									$("#progressbar").css("width", 98 + "%");
								}
							} else if (str.indexOf("I/O Test Started") != -1) {
								p3 = p3 + 0.5;
								if (p3 < 90) {
									$("#progressbar").css("width", p3 + "%");
								} else {
									$("#progressbar").css("width", 90 + "%");
								}
							} else if (str.indexOf("Deployment Finished") != -1) {
								p2 = p2 + 1;
								if (p2 < 60) {
									$("#progressbar").css("width", p2 + "%");
								} else {
									$("#progressbar").css("width", 60 + "%");
								}
							} else if (str.indexOf("Deployment Started") != -1) {
								p1 = p1 + 0.3;
								if (p1 < 40) {
									$("#progressbar").css("width", p1 + "%");
								} else {
									$("#progressbar").css("width", 40 + "%");
								}
							} else {
								$("#progressbar").css("width", 50 + "%");
							}
						});
						// $("#runTest").attr("disabled",true);
					}
				});
			};

			begincheck = function() {
				getSelectList();
				$.getJSON(path, function(data) {
					if (data["data"] == "200" || document.getElementById("tool").value != "vdbench") {
						$("#uploadBinary").hide();
					} else
						$("#uploadBinary").show();
				});
				var url = "https://" + window.location.host + "/VMtest/istestfinish";
				$.getJSON(url, function(data) {
					if (data["data"] != "200") {
						$('#myModal').modal('hide');
						clearInterval(time);
						// $("#runTest").removeAttr("disabled");
					} else {
						//$('#myModal').modal('show');
						//$("#progress").show();
						$("#cancelprocess").show();
						var mypath = "https://" + window.location.host + "/VMtest/readlog";
						$.getJSON(mypath, function(data2) {
							var str = data2["data"];
							$("#pcontent").html(str);
							if (str.indexOf("Testing Finished") == 0) {
								$("#progressbar").css("width", "100%");
							} else if (str.indexOf("I/O Test Finished") != -1) {
								p4 = p4 + 1;
								if (p3 < 98) {
									$("#progressbar").css("width", p4 + "%");
								} else {
									$("#progressbar").css("width", 98 + "%");
								}
							} else if (str.indexOf("I/O Test Started") != -1) {
								p3 = p3 + 0.5;
								if (p3 < 90) {
									$("#progressbar").css("width", p3 + "%");
								} else {
									$("#progressbar").css("width", 90 + "%");
								}
							} else if (str.indexOf("Deployment Finished") != -1) {
								p2 = p2 + 1;
								if (p2 < 60) {
									$("#progressbar").css("width", p2 + "%");
								} else {
									$("#progressbar").css("width", 60 + "%");
								}
							} else if (str.indexOf("Deployment Started") != -1) {
								p1 = p1 + 0.3;
								if (p1 < 40) {
									$("#progressbar").css("width", p1 + "%");
								} else {
									$("#progressbar").css("width", 40 + "%");
								}
							} else {
								$("#progressbar").css("width", 50 + "%");
							}
						});
						// $("#runTest").attr("disabled",true);
					}
				});

			};

			$('#runValidation').click(function() {
				$("#myModal").modal("show");
				$("#pcontent").text("Validating the configuration...");
				$("#progress").show();
				$("#progressbar").css("width", 100 + "%");
				// $("#runValidation").attr("disabled", true);
				$.ajax({
					type : "post",
					dataType : "json",
					url : "https://" + window.location.host + "/VMtest/validatefile",
					async : true,
					success : function(data) {
						$('#myModal').modal('hide');
						$("#infoModal").modal("show");
						showInfoModel(data["data"]);
					}
				});
			});

			$('#runTest').click(function() {
				$("#myModal").modal("show");
				$("#pcontent").html("HCIBench Testing Started.<br>...<br>");
				$("#progressbar").css("width", 0 + "%");
				$("#progress").show();
				$("#cancelprocess").show();
				// $("#runTest").attr("disabled", true);
				$.ajax({
					type : "post",
					dataType : "json",
					url : "https://" + window.location.host + "/VMtest/runtest",
					async : true,
					success : function(data) {
						if (data["status"] == "200") {
							time = setInterval("istestfinish()", 3000);
						}
					}
				});
			});
			$('#cancelprocess').click(function() {
				// $("#cancelprocess").attr("disabled", true);
				clearInterval(time);
				$.ajax({
					type : "post",
					dataType : "json",
					url : "https://" + window.location.host + "/VMtest/killtest",
					async : true,
					success : function(data) {
						if (data["status"] == "200") {
							showModel("Test is killed");
							$("#cancelprocess").hide();
						}
					}
				});
			});

			$('#uploadVdbench').click(function() {
				var formdata = new FormData();
				var vbenchFile = document.getElementById("vdbenchfile").files;
				if (document.getElementById("vdbenchfile").value != "") {
					$('#myModal').modal("show");
					$("#pcontent").text("");
					$("#progress").show();
					$("#cancelprocess").hide();
					formdata.append("vdbenchfile", vbenchFile[0]);
					$.ajax({
						type : "post",
						contentType : false,
						processData : false,
						data : formdata,
						url : "https://" + window.location.host + "/VMtest/uploadvdbench",
						async : true,
						success : function(data) {
							if (data["status"] == "200") {
								$('#myModal').modal("show");
								$("#pcontent").text("Upload finished");
								$("#progress").hide();
								$("#uploadBinary").hide();
							}
						}
					});
				} else {
					$('#myModal').modal("show");
					$("#pcontent").text("Please select a file");
					$("#progress").hide();				
				}
			});

			$('#uploadParamfile').click(function() {
				var formdata = new FormData();
				var paramFile = document.getElementById("paramfile").files;
				var toolParam = document.getElementById("tool").value;
				if (document.getElementById("paramfile").value != "") {
					$('#myModal').modal("show");
					$("#pcontent").text("");
					$("#progress").show();
					$("#cancelprocess").hide();
					formdata.append("paramfile", paramFile[0]);
					formdata.append("tool", toolParam);
					$.ajax({
						type : "post",
						contentType : false,
						processData : false,
						data : formdata,
						url : "https://" + window.location.host + "/VMtest/uploadParamfile",
						async : true,
						success : function(data) {
							if (data["status"] == "200") {
								$('#myModal').modal("show");
								$("#pcontent").text("Upload finished");
								$("#progress").hide();
								$("#uploadBinary").hide();
								getSelectList();
							}
						}
					});
				} else {
					$('#myModal').modal("show");
					$("#pcontent").text("Please select a file");
					$("#progress").hide();		
				}
			});

			$('#seeresult').click(function() {
				javascript: window.open("http://" + window.location.hostname + "/results/");
			});

			$('#download').click(function() {
				javascript: window.open("http://www.oracle.com/technetwork/server-storage/vdbench-downloads-1901681.html");
			});

			$('#generate').click(function() {
				var num = $("#diskNum").val();
				var tool = $("#tool").val();
				javascript: window.open("config/generate.html?disknum=" + num + "&tool=" + tool);
			});

			$('#saveResult').click(function() {
				$.ajax({
					type : "post",
					dataType : "json",
					url : "https://" + window.location.host + "/VMtest/zipfile",
					async : true,
					success : function(data) {
						if (data["status"] == "200") {
							window.open("https://" + window.location.host + "/VMtest/downloadFile?tmpName=" + data["name"], '_blank');
						}
					}
				});
			});

			$.getJSON(path3, function(data) {
				if (!jQuery.isEmptyObject(data)) {
					$("#vcenterIp").val(data["vc"].replace(/''/g, "'"));
					$("#vcenterName").val(data["vc_username"].replace(/''/g, "'"));
					// $("#vcenterPwd").val(data["vc_password"].replace(/''/g,"'"));
					$("#dcenterName").val(data["datacenter_name"].replace(/''/g, "'"));
					$("#clusterName").val(data["cluster_name"].replace(/''/g, "'"));
					$("#rpName").val(data["resource_pool_name"].replace(/''/g, "'"));
					$("#fdName").val(data["vm_folder_name"].replace(/''/g, "'"));
					$("#networkName").val(data["network_name"].replace(/''/g, "'"));
					if (data["static_ip_prefix"].indexOf("Customize") != -1){
					    var startingIp = data["static_ip_prefix"].split(" ")[1]
					    var staticPrefix = data["static_ip_prefix"].split(" ")[0]
					    $("#staticIpprefix").val(staticPrefix.replace(/''/g, "'"));
					    $("#startingIp").val(startingIp.replace(/''/g, "'"));    
					}
					else
					    $("#staticIpprefix").val(data["static_ip_prefix"].replace(/''/g, "'"));
					$("#dstoreName").val(data["datastore_name"].replace(/''/g, "'"));
					$("#hosts").val(data["hosts"].replace(/''/g, "'"));
					$("#workloads").val(data["workloads"].split("\n").filter(function(e) {
						return e
					}));
					$("#hostName").val(data["host_username"].replace(/''/g, "'"));
					// $("#hostPwd").val(data["host_password"].replace(/''/g,"'"));
					$("#storagePolicy").val(data["storage_policy"].replace(/''/g, "'"));
					$("#vmPrefix").val(data["vm_prefix"].replace(/''/g, "'"));
					$("#vmNum").val(data["number_vm"].trim());
					$("#cpuNum").val(data["number_cpu"].trim());
					$("#ramSize").val(data["size_ram"].trim());
					$("#diskNum").val(data["number_data_disk"].trim());
					$("#diskSize").val(data["size_data_disk"].trim());
					$("#duration").val(data["testing_duration"].trim());
					$("#outPath").val(data["output_path"]);
				}
				if (data["static_enabled"] == "true") {
					$("#staticEnabled").attr("checked", true);
					$("#staticprefix").show();
					if (data["static_ip_prefix"].indexOf("Customize") != -1)
					    $("#starting_ip").show();
					else
					    $("#starting_ip").hide();
				} else {
					$("#staticEnabled").attr("checked", false);
					$("#staticprefix").hide();
					$("#starting_ip").hide();
				}
				var showHostsCrendential = false
				if (data["clear_cache"] == "true") {
					$("#clearCache").attr("checked", true);
					showHostsCrendential = true;
				} else {
					$("#clearCache").attr("checked", false);
				}
				
				if (data["vsan_debug"] == "true") {
					$("#vsanDebug").attr("checked", true);
					showHostsCrendential = true;
				} else {
					$("#vsanDebug").attr("checked", false);
				}
				
				if (showHostsCrendential == false){
				    $("#host_credential").hide();
				} else {
				    $("#host_credential").show();
				}

				if (data["reuse_vm"] == "false") {
					$("#reuseVM").attr("checked", false);
				} else
					$("#reuseVM").attr("checked", true);

				if (data["easy_run"] == "true") {
					$("#easyRun").attr("checked", true);
					$("#complex").hide();
					$("#easyRunWorkloads").show();
				} else {
					$("#easyRun").attr("checked", false);
					$("#complex").show();
					$("#easyRunWorkloads").hide();
				}

				if (data["deploy_on_hosts"] == "true") {
					$("#deployHost").attr("checked", true);
					$("#hosts_list").show();
				} else {
					$("#deployHost").attr("checked", false);
					$("#hosts_list").hide();
				}

				$("#warmUp").val(data["warm_up_disk_before_testing"]);
				$("#tool").val(data["tool"]);

				if (data["cleanup_vm"] == "true") {
					$("#cleanUp").attr("checked", true);
				}
			});

			$("#refresh").click(function() {
				getSelectList();
				alert("Refresh Done");
			});

			$("#deleteItem").click(function() {
				var toolParam = document.getElementById("tool").value;
				var selectVdbench = $("#selectparam  option:selected").text();
				if (selectVdbench != "") {
					$.ajax({
						type : "post",
						dataType : "json",
						url : "https://" + window.location.host + "/VMtest/deleteFile?name=" + selectVdbench + "&tool=" + toolParam,
						async : true,
						success : function(data) {
							if (data["status"] == "200") {
								getSelectList();
								alert("Delete Success");
							}
						}
					});
				} else {
					alert("Please select a param file to delete");
				}
			});
			
			$('#cleanVms').click(function(){
			    $("#myModal").modal("show");
			    $("#pcontent").text("");
			    $("#progress").show();
			    $("#cancelprocess").hide();
			    $.ajax({
				type : "post",
				dataType : "json",
				url : "https://" + window.location.host + "/VMtest/cleanupvms",
				async : true,
				success : function(data) {
				    if (data["status"] == "200") {
					showModel(data["content"]);
				} else {
					showModel(data["issue"]);
				}
				}
			});
			});

			$('#saveForm').click(
					function() {
						$("#myModal").modal("show");
						$("#pcontent").text("");
						$("#progress").show();
						$("#cancelprocess").hide();
						var flag = true;
						var formdata = new FormData();
						var vcenterIp = $("#vcenterIp").val();
						var vcenterName = $("#vcenterName").val();
						var vcenterPwd = $("#vcenterPwd").val();
						var dcenterName = $("#dcenterName").val();
						var clusterName = $("#clusterName").val();
						var rpName = $("#rpName").val();
						var fdName = $("#fdName").val();
						var networkName = $("#networkName").val();
						var dstoreName = $("#dstoreName").val();
						var deployHost;
						if ($("#deployHost").is(':checked')) {
							deployHost = "true";
						} else {
							deployHost = "false";
						}
						var hosts = $("#hosts").val();
						var workloads = $("#workloads").val();
						var hostName = $("#hostName").val();
						var hostPwd = $("#hostPwd").val();
						var storagePolicy = $("#storagePolicy").val();
						var vmPrefix = $("#vmPrefix").val();
						var vmNum = $("#vmNum").val();
						var cpuNum = $("#cpuNum").val();
						var ramSize = $("#ramSize").val();
						var diskNum = $("#diskNum").val();
						var diskSize = $("#diskSize").val();
						var filePath = $("#filePath").val();
						var outPath = $("#outPath").val();
						var warmUp = $("#warmUp").val();
						var tool = $("#tool").val();
						var selectVdbench = $("#selectparam  option:selected").text();
						var staticEnabled;
						var staticIpprefix;
						var startingIp;
						
						if ($("#staticEnabled").is(':checked')) {
							staticEnabled = "true";
							staticIpprefix = $("#staticIpprefix").val();
							if (staticIpprefix.indexOf("Customize") != -1){
							    startingIp = $("#startingIp").val();
							    staticIpprefix = "Customize" + " " + startingIp;
							}
						} else {
							staticEnabled = "false";
							staticIpprefix = "";
						}
						var easyRun;
						if ($("#easyRun").is(':checked')) {
							easyRun = "true";
						} else {
							easyRun = "false";
						}
						var clearCache;
						if ($("#clearCache").is(':checked')) {
							clearCache = "true";
						} else {
							clearCache = "false";
						}
						var vsanDebug;
						if ($("#vsanDebug").is(':checked')) {
						    vsanDebug = "true";
						} else {
						    vsanDebug = "false";
						}
						var reuseVM;
						if ($("#reuseVM").is(':checked')) {
							reuseVM = "true";
						} else {
							reuseVM = "false";
						}
						var duration = $("#duration").val();
						var cleanUp;
						if ($("#cleanUp").is(':checked')) {
							cleanUp = "true";
						} else {
							cleanUp = "false";
						}
						var msg = "";
						if (vcenterIp == "") {
							flag = false;
							msg += " vCenter IP Address,";
						}
						if (vcenterName == "") {
							flag = false;
							msg += " vCenter Username,";
						}

						/*
						 * if ((jQuery.isEmptyObject(data)
						 * ||data["vc_password"] == "") &&
						 * vcenterPwd == ""){ flag = false; msg += "
						 * vCenter Password,"; }
						 */

						if (dcenterName == "") {
							flag = false;
							msg += " Datecenter name,";
						}
						if (clusterName == "") {
							flag = false;
							msg += " Cluster Name,";
						}
						if (dstoreName == "") {
							flag = false;
							msg += " Datastore Name,";
						}
						if ((easyRun == "true") && (workloads == null)) {
							flag = false;
							msg += " Easy Run Workloads,"
						}
						if ((vmNum == "") && (easyRun == "false")) {
							flag = false;
							msg += " Number of VMs,";
						}
						if ((cpuNum == "") && (easyRun == "false")) {
							flag = false;
							msg += " Number of CPU,";
						}
						if ((ramSize == "") && (easyRun == "false")) {
							flag = false;
							msg += " Size of Memory,";
						}
						if ((selectVdbench == "") && (easyRun == "false")) {
							flag = false;
							msg += " Workload Parameter File Selection,"
						}
						if ($("#clearCache").is(':checked') || $("#vsanDebug").is(':checked')) {
						    if (hostName == "") {
							flag = false;
							msg += " Host Username,";
							}
							/*
							 * if ((jQuery.isEmptyObject(data) ||
							 * data["host_password"] == "") &&
							 * hostPwd == ""){ flag = false; msg += "
							 * Host Password,"; }
							 */
						}
						if ($("#staticEnabled").is(':checked') && $("#staticIpprefix").val().indexOf("Customize") != -1) {
						    if (!/((25[0-5])|(2[0-4]\d)|(1\d\d)|([1-9]?\d))((^|\.)((25[0-5])|(2[0-4]\d)|(1\d\d)|([1-9]?\d))){3}\/([1-2][0-9]|[0-9]|3[0-2])$/.test(startingIp))
						    {
							showModel("The customized starting IP/Subnet Size is not following the pattern xxx.xxx.xxx.xxx/xx, e.g. 10.0.0.1/24");
							return;
						    }
						}
							
						if ($("#deployHost").is(':checked')) {
							if (hosts == "") {
								flag = false;
								msg += " Host,";
							}
						}
						if (!flag) {
							msg += " cannot be empty!";
							showModel(msg);
							return;
						}
						if (dstoreName != "") {
							var length = 0;
							var lines = dstoreName.split(/\r\n|\r|\n/);
							for (var i = 0; i < lines.length; i++) {
								if (lines[i].trim() != "")
									length++;
							}
							var rem = vmNum % length;
							if ((rem != 0) && (easyRun == "false")) {
								showModel("Your input is " + vmNum + " test VMs and " + length + " datastores." + " However, " + vmNum + " cannot be fully divided by " + length + "."
										+ " This is not acceptable since this will cause VMs not evenly distributed onto these datastores. " + "Please modify the Number of VMs.");
								return;
							}
						}
						if ($("#uploadBinary").is(":visible")) {
							showModel("Please upload Vdbench zip file before saving configuration")
							return;
						}
						// $('#saveForm').attr("disabled",true);
						formdata.append("vcenterIp", vcenterIp.trim());
						formdata.append("vcenterName", vcenterName.trim());
						formdata.append("vcenterPwd", vcenterPwd);
						formdata.append("dcenterName", dcenterName.trim());
						formdata.append("clusterName", clusterName.trim());
						formdata.append("rpName", rpName.trim());
						formdata.append("fdName", fdName.trim());
						formdata.append("networkName", networkName.trim());
						formdata.append("staticIpprefix", staticIpprefix);
						formdata.append("staticEnabled", staticEnabled);
						formdata.append("dstoreName", dstoreName.trim());
						formdata.append("deployHost", deployHost);
						formdata.append("hosts", hosts.trim());
						formdata.append("workloads", workloads);
						formdata.append("hostName", hostName.trim());
						formdata.append("hostPwd", hostPwd);
						formdata.append("easyRun", easyRun);
						formdata.append("clearCache", clearCache);
						formdata.append("vsanDebug", vsanDebug);
						formdata.append("storagePolicy", storagePolicy.trim());
						formdata.append("vmPrefix", vmPrefix.trim());
						formdata.append("vmNum", vmNum);
						formdata.append("cpuNum", cpuNum);
						formdata.append("ramSize", ramSize);
						formdata.append("diskNum", diskNum);
						formdata.append("diskSize", diskSize);
						formdata.append("reuseVM", reuseVM);
						formdata.append("filePath", filePath);
						formdata.append("outPath", outPath.trim());
						formdata.append("warmUp", warmUp);
						formdata.append("tool", tool);
						formdata.append("duration", duration);
						formdata.append("cleanUp", cleanUp);
						formdata.append("selectVdbench", selectVdbench)
						$.ajax({
							type : "post",
							contentType : false,
							processData : false,
							data : formdata,
							url : "https://" + window.location.host + "/VMtest/generatefile",
							async : true,
							success : function(data) {
								// $('#myModal').modal('hide');
								// $("#saveForm").removeAttr("disabled");
								if (data["status"] == "200") {
									showModel("Finished");
									$("#runValidation").attr("disabled", false);
									$("#runTest").attr("disabled", false);
								} else {
									showModel(data["issue"]);
								}
							}
						});
					});
		});