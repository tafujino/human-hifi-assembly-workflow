# yak (https://github.com/lh3/yak) の実行ファイルと、
# 同リポジトリに含まれる groupxy.pl (chrX/chrY パーティショニング用スクリプト) を
# 含んだイメージ。bioconda の yak パッケージには groupxy.pl が含まれないため、
# ソースからビルドして両方を取得する。
#
# yak は sexchr サブコマンド/groupxy.pl 追加後にタグが打たれていない
# (最新タグ v0.1 はそれらの追加より前の 2020 年時点のもの) ため、
# 再現性のため特定のコミットを固定して取得する。
FROM ubuntu:22.04

ARG YAK_COMMIT=ef033d720e229593b32ad454af14ccea2120ec13

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      zlib1g-dev \
      ca-certificates \
      git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/lh3/yak.git /opt/yak \
    && git -C /opt/yak checkout "${YAK_COMMIT}" \
    && make -C /opt/yak \
    && install -m 0755 /opt/yak/yak /usr/local/bin/yak \
    && install -m 0755 /opt/yak/groupxy.pl /usr/local/bin/groupxy.pl \
    && rm -rf /opt/yak

WORKDIR /data
