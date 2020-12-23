#! /bin/sh
##
## 此脚本用于自动化搭建orion(猎户座)节点
##
## 注意事项：
## 1. 此脚本已默认当前系统安装了docker服务并下载了最新的orion镜像
## 2. 配置文件只做修改不做新增或删除
## 3. 若存在异地组网情况，请先通过docker swarm创建overlay网络，并注意网络名称必须为besunetwork
##
## 配置内容（样例）：
## deploy_path=/home/yzh/Documents/docker/orion                  # 部署地址
## source_conf=/home/yzh/Documents/besu/orion_node               # 配置文件路径
## docker_image=consensys/quorum-orion:20.10.0                   # 镜像名称
## passwords=yzh20201223 yzh20201224 yzh20201225                 # 权限密码
## static_ip=192.18.0.253                                        # 静态ip地址
##
## @Date：2020-11-12
## @Author：yuanzhenhui
##

# 获取部署节点路径
deploy_path=$(sed '/^deploy_path=/!d;s/.*=//' generate_conf/orionnode.cnf)

# 配置文件模板
source_conf=$(sed '/^source_conf=/!d;s/.*=//' generate_conf/orionnode.cnf)

# docker镜像名称
docker_image=$(sed '/^docker_image=/!d;s/.*=//' generate_conf/orionnode.cnf)

# 设置密码
passwords=$(sed '/^passwords=/!d;s/.*=//' generate_conf/orionnode.cnf)

# 节点静态ip
static_ip=$(sed '/^static_ip=/!d;s/.*=//' generate_conf/orionnode.cnf)

# 1. 先判断是否已经存在部署目录，若没有部署过才执行下面的生成操作。这是怕误删了之前已有的文件，脚本中不存在删除的语句，可以避免因别人误操作而怪罪到头上的情况。
if [ ! -d $deploy_path ]; then

  # 2. 创建部署目录并设置权限
  sudo mkdir -p $deploy_path && sudo chmod 777 -R $deploy_path

  # 3. 创建密码文件并赋予权限
  sudo touch $deploy_path/passwordFile && sudo chmod 777 $deploy_path/passwordFile

  # 4. 将配置文件中的密码字符串转换为数组
  password_arr=($passwords)

  # 5. 循环遍历密码数组
  for i in "${!password_arr[@]}"; do

    # 6. 将遍历出来的密码写入到密码文件中
    echo -e ${password_arr[i]} >>$deploy_path/passwordFile

    # 7. 输出写入到密码文件中的密码明文
    echo "password is : "${password_arr[i]}

    # 8. 使用sudo启动docker并生成密码明文命名的加密后非对称密码文件
    sudo docker run -i --rm --mount type=bind,source=$deploy_path,target=/data $docker_image -g /data/${password_arr[i]}Key

    # 9. 将非对称密码文件名称装入写入变量为后面使用
    pub="$pub\"/data/${password_arr[i]}Key.pub\","
    prv="$prv\"/data/${password_arr[i]}Key.key\","
  done

  # 10. 拷贝orion.conf文件到部署目录并赋予777权限
  orion_conf=$source_conf"/orion.conf"
  sudo cp $orion_conf $deploy_path && sudo chmod 777 -R $deploy_path

  # 11. 将部署目录中的orion.conf中”<IP_ADDRESS>“字样替换成节点固定ip地址
  orionconfg=$deploy_path"/"${orion_conf##*/}
  sudo sed -i "s/<IP_ADDRESS>/$static_ip/g" $orionconfg

  # 12. 将刚才非对称密码文件名写入orion.conf中
  echo -e "publickeys = [${pub%?}] \n privatekeys = [${prv%?}]" >>$orionconfg

  # 13. 在配置文件目录中创建一个名为keySub的新目录并赋权
  sudo mkdir -p $source_conf"/keySub" && sudo chmod 777 -R $source_conf"/keySub"

  # 14. 将部署目录中生成好的passwordFile和后缀名为”pub“的公钥全部拷贝到keySub中
  sudo cp -rf $deploy_path/passwordFile $source_conf"/keySub/"
  sudo cp -rf $deploy_path/*.pub $source_conf"/keySub/"

  # 15. 执行启动Orion docker镜像并挂载配置文件路径
  sudo docker run --name a_orion --network=besunetwork --ip=$static_ip -p 8080:8080 -p 8888:8888 --mount type=bind,source=$deploy_path,target=/data -d $docker_image /data/orion.conf
fi
