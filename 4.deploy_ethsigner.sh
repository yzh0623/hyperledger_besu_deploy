#! /bin/sh
##
## 此脚本用于自动化部署eth_signer节点
##
## 注意事项：
## 1. 本脚本默认当前系统已安装cnpm（nodejs）并在脚本同目录下安装好web3的node项目
## 2. 本脚本默认当前系统已预先安装jq工具
## 3. 本脚本默认当前系统已经安装了docker服务并下载了最新的eth_signer镜像
## 4. 在异地组网的情况下本脚本将建立在docker swarm overlay网络下，因此先确保当前docker容器已经加入到overlay网络
## 5. 配置文件只做修改不做新增或删除
##
## 配置内容（样例）：
## deploy_path=/home/yzh/Documents/docker/ethsigner 							# 获取部署节点路径
## createkey_path=/home/yzh/Documents/besu/ethsigner_conf/createKeyfile.js 		# ethsigner用户密码js文件路径
## docker_image=consensys/quorum-ethsigner:20.10.0 								# docker镜像名称
## signer_pwds=master@2020 slave@2020 											# signer密码数组
## chain_id=76387 																# 区块链的链id（可以在创世块配置文件中获取）
## custom_name=a_signer 														# 节点服务名称
## ethsigner_ip=192.18.0.6 														# 固定ip地址
## signer_node_ip=192.18.0.5 													# 签署节点具体ip地址
## has_users=/home/yzh/Documents/besu/ethsigner_conf/users						# 是否存在用户信息
##
## @Date：2020-11-25
## @Author：yuanzhenhui
##

# 获取部署节点路径
deploy_path=$(sed '/^deploy_path=/!d;s/.*=//' generate_conf/ethsigner.cnf)

# ethsigner用户密码js文件路径
createkey_path=$(sed '/^createkey_path=/!d;s/.*=//' generate_conf/ethsigner.cnf)

# docker镜像名称
docker_image=$(sed '/^docker_image=/!d;s/.*=//' generate_conf/ethsigner.cnf)

# signer密码数组
signer_pwds=$(sed '/^signer_pwds=/!d;s/.*=//' generate_conf/ethsigner.cnf)

# 区块链的链id
chain_id=$(sed '/^chain_id=/!d;s/.*=//' generate_conf/ethsigner.cnf)

# 自定义节点名称
custom_name=$(sed '/^custom_name=/!d;s/.*=//' generate_conf/ethsigner.cnf)

# 固定ip地址
ethsigner_ip=$(sed '/^ethsigner_ip=/!d;s/.*=//' generate_conf/ethsigner.cnf)

# 签署节点固定ip
signer_node_ip=$(sed '/^signer_node_ip=/!d;s/.*=//' generate_conf/ethsigner.cnf)

# 是否存在用户
has_users=$(sed '/^has_users=/!d;s/.*=//' generate_conf/ethsigner.cnf)

if [ ! -d $deploy_path ]; then

	# 1. 判断是否存在部署目录和是否已经存在用户了
	if [ ! -d $has_users ]; then

		# 2. 若不存在则创建部署目录和用户目录
		sudo mkdir -p $deploy_path && sudo mkdir -p $deploy_path/signer_address
		sudo mkdir -p $has_users && sudo chmod 777 -R $has_users

		# 3. 将密码信息转换成数组并通过循环读取每一个密码信息
		signer_pwd_arr=($signer_pwds)
		for i in "${!signer_pwd_arr[@]}"; do

			# 4. 生成签署账号64位的私钥
			hex_address=$(openssl rand -hex 32)

			# 5. 然后通过执行createkey.js生成密钥信息
			keyfile=$(node $createkey_path "0x"$hex_address ${signer_pwd_arr[i]})

			# 6. 通过解析返回的json获取到签署节点的加密密文
			address_val=$(echo $keyfile | jq '.address')
			address_val=$(echo $address_val | sed 's/\"//g')

			# 7. 根据上面收集的内容生成keyFile、passwordFile和配置用的toml文件
			keyFilePath=$deploy_path/$address_val/keyFile
			passwordFilePath=$deploy_path/$address_val/passwordFile
			tomlFilePath=$deploy_path/signer_address/$address_val".toml"

			# 8. 将信息按照要求写入到指定的文件里面，这里需要注意的配置文件中关于路径的写法一定要按照镜像中机器的写法不然是没有找到对应路径的
			sudo mkdir -p $deploy_path/$address_val
			sudo touch $keyFilePath && sudo touch $passwordFilePath && sudo touch $tomlFilePath
			sudo chmod 777 -R $deploy_path

			# 9. 将密码写入到passwordFile
			echo -e "${signer_pwd_arr[i]}" >>$passwordFilePath

			# 10. 将生成的key内容写入keyFile
			echo -e "$keyfile" >>$keyFilePath

			# 11. 将权限配置文件写入toml配置
			echo -e "[metadata]" >>$tomlFilePath
			echo -e "createdAt = $(date "+%Y-%m-%d %H:%M:%S")" >>$tomlFilePath
			echo -e "description = \"$hex_address account configuration\" \n" >>$tomlFilePath
			echo -e "[signing] \ntype = \"file-based-signer\"" >>$tomlFilePath
			echo -e "key-file = \"/var/lib/ethsigner/$address_val/keyFile\"" >>$tomlFilePath
			echo -e "password-file = \"/var/lib/ethsigner/$address_val/passwordFile\"" >>$tomlFilePath
		done

		# 12. 将配置信息进行备份
		sudo cp -rf $deploy_path/* $has_users
	else
		sudo mkdir -p $deploy_path
		sudo cp -rf $has_users/* $deploy_path
	fi
	# 13. 使用docker来启动eth_signer
	sudo docker run --name $custom_name --network=besunetwork --ip $ethsigner_ip -p 8945:8545 --mount type=bind,source=$deploy_path,target=/var/lib/ethsigner -d $docker_image --chain-id=$chain_id --downstream-http-host=$signer_node_ip --downstream-http-port=8545 --http-listen-host=0.0.0.0 multikey-signer --directory=/var/lib/ethsigner/signer_address
fi
