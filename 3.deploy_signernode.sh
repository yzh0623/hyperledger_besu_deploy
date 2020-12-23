#! /bin/sh
##
## 此脚本用于自动化搭建hyperledger besu的签署节点
##
## 注意事项：
## 1. 本脚本默认当前系统已经安装了docker服务并下载了最新的besu镜像
## 2. 在异地组网的情况下本脚本将建立在docker swarm overlay网络下，因此先确保当前docker容器已经加入到overlay网络
## 3. 在执行此脚本之前请先将Orion（猎户座）节点部署完毕，Orion提供自动化部署脚本，详情可以参考 1.deploy_orion.sh 脚本
## 4. 配置文件只做修改不做新增或删除
##
## 配置内容（样例）：
## custom_folder=A_SIGN_NODE                                                  # 自定义签署节点名称
## deploy_path=/home/yzh/Documents/docker/besu/Clique                         # 签署节点部署路径
## clique_config_file=node_conf/a_boot_node_clique_config.toml                # clique节点配置文件路径
## genesis_config_file=genesis_conf/a_boot_node_clique_genesis.json           # 创世块文件路径
## signer_ip=192.18.0.5                                                       # 签署节点ip地址
## docker_image=hyperledger/besu:20.10.0-RC2-openjdk-latest                   # docker镜像名称
## orion_client=http://192.18.0.253:8888                                      # 猎户座客户端访问地址
## orion_folder=/home/yzh/Documents/besu/orion_node/keySub                    # orion部署目录
##
## @Date：2020-10-19
## @Author：yuanzhenhui
##

# 获取部署节点路径
deploy_path=$(sed '/^deploy_path=/!d;s/.*=//' generate_conf/signernode.cnf)

# 获取用户定义的节点文件夹名称
custom_folder=$(sed '/^custom_folder=/!d;s/.*=//' generate_conf/signernode.cnf)

# 获取配置文件
clique_config_file=$(sed '/^clique_config_file=/!d;s/.*=//' generate_conf/signernode.cnf)

# 获取创世块文件
genesis_config_file=$(sed '/^genesis_config_file=/!d;s/.*=//' generate_conf/signernode.cnf)

# 签署节点ip地址
signer_ip=$(sed '/^signer_ip=/!d;s/.*=//' generate_conf/signernode.cnf)

# docker镜像
docker_image=$(sed '/^docker_image=/!d;s/.*=//' generate_conf/signernode.cnf)

# 猎户座客户端url
orion_client=$(sed '/^orion_client=/!d;s/.*=//' generate_conf/signernode.cnf)

# orion节点目录
orion_folder=$(sed '/^orion_folder=/!d;s/.*=//' generate_conf/signernode.cnf)

# 1. 先判断发布目录是否存在如果不存在则新建部署目录并赋权
if [ ! -d $deploy_path ]; then
  sudo mkdir -p $deploy_path && sudo chmod 777 $deploy_path
fi

# 2. 根据部署目录整理出签署节点的具体路径
target_folder=$deploy_path"/"$custom_folder

# 3. 判断签署节点是否存在，如果不存在则先创建签署节点文件夹
if [ ! -d $target_folder ]; then
  sudo mkdir -p $target_folder

  # 4. 将创世块文件和Clique共识算法的配置文件拷贝到签署节点目录下
  sudo cp $genesis_config_file $target_folder && sudo cp $clique_config_file $target_folder

  # 5. 创建签署节点中data目录并将其赋权
  data_folder=$target_folder"/data"
  sudo mkdir -p $data_folder && sudo chmod 777 -R $target_folder

  # 6. 如果要则创建认证文件credential.toml
  credential_file=$target_folder"/data/credential.toml"
  sudo touch $credential_file && sudo chmod 777 $credential_file

  # 7. 创建passwordFile文档
  passwordFilePath=$orion_folder"/passwordFile"

  # 8. 通过循环读取passwordFile中的每一行内容
  for line in $(cat $passwordFilePath); do
    # 9. 获取到password内容并通过在后面加上”_name“将其变为用户名
    password=$line
    username=$password"_name"

    # 10. 按照生成规则将username变量写入credential.toml文件中
    echo -e "[Users.$username]" >>$credential_file

    # 11. 使用password hash --password=$password生成密码并赋值给crypt_pwd
    crypt_pwd=$(sudo docker run -i --rm $docker_image password hash --password=$password)

    # 12. 将生成好的密码写入credential.toml
    echo -e "password = \"$crypt_pwd\"" >>$credential_file
    echo -e "permissions=[\"*:*\"]" >>$credential_file

    # 13. 将Orion中生成的公钥打开并公钥内容写入到credential.toml中
    pubfilename=$orion_folder"/"$password"Key.pub"
    fileline=$(cat $pubfilename)
    echo -e "privacyPublicKey=\"$fileline\" \n" >>$credential_file
  done

  # 14. 将节点隐私规则打开并写入到clique_config_file文件中
  config_file=$target_folder"/"${clique_config_file##*/}
  echo -e "\n privacy-enabled=true # 启用隐私" >>$config_file
  echo -e "privacy-url=\"$orion_client\" # 隐私服务器地址" >>$config_file
  echo -e "privacy-multi-tenancy-enabled=true # 是否启用多租户" >>$config_file
  echo -e "rpc-http-authentication-enabled=true # rpc启动权限访问" >>$config_file
  echo -e "rpc-http-authentication-credentials-file=\"/var/lib/besu/data/credential.toml\" # rpc启动权限配置文件路径" >>$config_file

  # 15. 启动节点
  nodename=$(echo $custom_folder | tr '[A-Z]' '[a-z]')
  sudo docker run --name $nodename --network=besunetwork --ip $signer_ip -p 30303:30303 -p 8545:8545 -p 8546:8546 -v $target_folder:/var/lib/besu -d $docker_image --config-file=/var/lib/besu/${clique_config_file##*/}
fi
