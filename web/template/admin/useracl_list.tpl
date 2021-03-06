<!doctype html public "-//w3c//dtd html 4.0 transitional//en">
<html>
<head>
<title>自动登陆用户列表</title>
<meta name="generator" content="editplus">
<meta name="author" content="nuttycoder">
<link href="{{$template_root}}/all_purpose_style.css" rel="stylesheet" type="text/css" />
</head>

<body>


	<table width="100%" border="0" cellspacing="0" cellpadding="0">
  <tr>
    <td  class="hui_bj">用户管理——详细信息</td>
  </tr>
  <tr>
	<td class="main_content">
		<table bordercolor="white" cellspacing="1" cellpadding="5" border="0" width="100%"  class="BBtable">
			<tr>
				<th class="list_bg"  width="20%">地址</th>
				<th class="list_bg"  width="10%">连接类型</th>
				<th class="list_bg"  width="10%">本地用户</th>
				{{if $admin_level == 0}}
				<th class="list_bg"  width="10%">远程用户</th>
				<th class="list_bg"  width="10%">密&nbsp;&nbsp;码</th>
				{{/if}}
				<th class="list_bg"  width="20%">操作</th>
			</tr>
			{{section name=t loop=$alluser}}
			{{if $adminname == $alluser[t].localuser || $admin_level == 1}} 
			<tr {{if $smarty.section.t.index % 2 == 0}}bgcolor="f7f7f7"{{/if}}>
				
				<td>{{$alluser[t].addr}}</td>
				<td>{{$alluser[t].type}}</ td>
				<td>{{$alluser[t].localuser}}</ td>
				{{if $admin_level == 0}}
				<td>{{$alluser[t].remoteuser|escape:'htmlall'}}</ td>
				<td>{{$alluser[t].password}}</ td>
				{{/if}}
				<td>{{if $admin_level == 1}}<img src="{{$template_root}}/images/scico.gif" width="16" height="16" align="absmiddle"><a href="#" onClick="if(!confirm('您确定要删除用户？')) {return false;} else { location.href='admin.php?controller=admin_auto&action=user_del&id={{$alluser[t].id}}'; }" >删除</a> |{{/if}} <img src="{{$template_root}}/images/ckico.gif" width="16" height="16" align="absmiddle"><a href="admin.php?controller=admin_auto&action=user_edit&type=old&id={{$alluser[t].id}}">修改</a></td>
			</tr>
			{{/if}}
			{{/section}}
			<tr>
				<td colspan="4" align="right">
					共{{$row_num}}条  {{$page_list}}  页次：{{$curr_page}}/{{$total_page}}页  {{$items_per_page}}条日志/页  转到第<input name="pagenum" type="text" class="wbk" size="2" onKeyPress="if(event.keyCode==13) window.location='admin.php?controller=admin_session&action=dangerlist&page='+this.value;">页
				</td>
			</tr>
		</table>
	</td>
  </tr>
</table>

<script language="javascript">

function my_confirm(str){
	if(!confirm(str + "？"))
	{
		window.event.returnValue = false;
	}
}

</script>
</body>
<iframe name="hide" height="0" frameborder="0" scrolling="no"></iframe>
</html>



