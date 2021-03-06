花花写于2020.1.6
本系列是我的`TCGA`学习记录，跟着**生信技能树B站课程**学的，已获得授权（嗯，真的_）。课程链接：`https://www.bilibili.com/video/av49363776`

目录：

[TCGA-1.数据下载](https://links.jianshu.com/go?to=https%3A%2F%2Fmp.weixin.qq.com%2Fs%2FZl8V4qKyY12wfyP-58t3Rg)

[TCGA2.GDC数据整理](https://links.jianshu.com/go?to=https%3A%2F%2Fmp.weixin.qq.com%2Fs%2FaFq-YQYVvn8vYyOHH1mRiQ)

[TCGA3.R包TCGA-biolinks下载数据](https://links.jianshu.com/go?to=https%3A%2F%2Fmp.weixin.qq.com%2Fs%2FGl21j3Rl_kv8KIsB9LDp4g)

### 1.准备R包

```r
if(!require(stringr))install.packages('stringr')
if(!require(ggplotify))install.packages("ggplotify")
if(!require(patchwork))install.packages("patchwork")
if(!require(cowplot))install.packages("cowplot")
if(!require(DESeq2))install.packages('DESeq2')
if(!require(edgeR))install.packages('edgeR')
if(!require(limma))install.packages('limma')
```

### 2.准备数据
本示例的数据是TCGA-KIRC的表达矩阵。tcga样本编号14-15位是隐藏分组信息的,详见：
[TCGA的样本id里藏着分组信息](https://mp.weixin.qq.com/s/UohDh5fHkTPlwNp43ivWHg)


```r
rm(list = ls())
load("tcga_kirc_exp.Rdata") #表达矩阵expr
dim(expr)
```

```
## [1] 552 593
```

```r
group_list <- ifelse(as.numeric(str_sub(colnames(expr),14,15))<10,"tumor","normal")
group_list <- factor(group_list,levels = c("normal","tumor"))
table(group_list)
```

```
## group_list
## normal  tumor 
##     71    522
```

### 3.三大R包的差异分析

#### 3.1 Deseq2

```r
library(DESeq2)
colData <- data.frame(row.names =colnames(expr), 
                      condition=group_list)
dds <- DESeqDataSetFromMatrix(
  countData = expr,
  colData = colData,
  design = ~ condition)
#参考因子应该是对照组 dds$condition <- relevel(dds$condition, ref = "untrt")

dds <- DESeq(dds)
# 两两比较
res <- results(dds, contrast = c("condition",rev(levels(group_list))))
resOrdered <- res[order(res$pvalue),] # 按照P值排序
DEG <- as.data.frame(resOrdered)
head(DEG)
# 去除NA值
DEG <- na.omit(DEG)

#添加change列标记基因上调下调
#logFC_cutoff <- with(DEG,mean(abs(log2FoldChange)) + 2*sd(abs(log2FoldChange)) )
logFC_cutoff <- 1
DEG$change = as.factor(
  ifelse(DEG$pvalue < 0.05 & abs(DEG$log2FoldChange) > logFC_cutoff,
         ifelse(DEG$log2FoldChange > logFC_cutoff ,'UP','DOWN'),'NOT')
)
head(DEG)

DESeq2_DEG <- DEG
```

#### 3.2 edgeR

```r
library(edgeR)

dge <- DGEList(counts=expr,group=group_list)
dge$samples$lib.size <- colSums(dge$counts)
dge <- calcNormFactors(dge) 

design <- model.matrix(~0+group_list)
rownames(design)<-colnames(dge)
colnames(design)<-levels(group_list)

dge <- estimateGLMCommonDisp(dge,design)
dge <- estimateGLMTrendedDisp(dge, design)
dge <- estimateGLMTagwiseDisp(dge, design)

fit <- glmFit(dge, design)
fit2 <- glmLRT(fit, contrast=c(-1,1)) 

DEG=topTags(fit2, n=nrow(expr))
DEG=as.data.frame(DEG)
logFC_cutoff <- with(DEG,mean(abs(logFC)) + 2*sd(abs(logFC)) )
logFC_cutoff <- 1
DEG$change = as.factor(
  ifelse(DEG$PValue < 0.05 & abs(DEG$logFC) > logFC_cutoff,
         ifelse(DEG$logFC > logFC_cutoff ,'UP','DOWN'),'NOT')
)
head(DEG)
```

```
##                   logFC    logCPM       LR        PValue           FDR
## hsa-mir-508   -4.264945 5.3610815 825.7952 1.329948e-181 7.341313e-179
## hsa-mir-514-3 -4.262325 3.5005425 674.3829 1.112883e-148 3.071556e-146
## hsa-mir-514-2 -4.258203 3.4771070 658.6855 2.885406e-145 5.309148e-143
## hsa-mir-506   -5.522829 0.7477531 654.6812 2.143124e-144 2.957511e-142
## hsa-mir-514-1 -4.271951 3.4852217 642.0128 1.219493e-141 1.346320e-139
## hsa-mir-514b  -5.956182 0.3742949 579.5893 4.606971e-128 4.238413e-126
##               change
## hsa-mir-508     DOWN
## hsa-mir-514-3   DOWN
## hsa-mir-514-2   DOWN
## hsa-mir-506     DOWN
## hsa-mir-514-1   DOWN
## hsa-mir-514b    DOWN
```

```r
table(DEG$change)
```

```
## 
## DOWN  NOT   UP 
##   64  368  120
```

```r
edgeR_DEG <- DEG
```

#### 3.limma-voom

```r
library(limma)

design <- model.matrix(~0+group_list)
colnames(design)=levels(group_list)
rownames(design)=colnames(expr)

dge <- DGEList(counts=expr)
dge <- calcNormFactors(dge)
logCPM <- cpm(dge, log=TRUE, prior.count=3)

v <- voom(dge,design, normalize="quantile")
fit <- lmFit(v, design)

constrasts = paste(rev(levels(group_list)),collapse = "-")
cont.matrix <- makeContrasts(contrasts=constrasts,levels = design) 
fit2=contrasts.fit(fit,cont.matrix)
fit2=eBayes(fit2)

DEG = topTable(fit2, coef=constrasts, n=Inf)
DEG = na.omit(DEG)
#logFC_cutoff <- with(DEG,mean(abs(logFC)) + 2*sd(abs(logFC)) )
logFC_cutoff <- 1
DEG$change = as.factor(
  ifelse(DEG$P.Value < 0.05 & abs(DEG$logFC) > logFC_cutoff,
         ifelse(DEG$logFC > logFC_cutoff ,'UP','DOWN'),'NOT')
)
head(DEG)
```

```
##                  logFC   AveExpr         t       P.Value     adj.P.Val
## hsa-mir-141  -5.492612  2.990323 -31.22459 1.280624e-127 7.069043e-125
## hsa-mir-200c -5.333666  5.687063 -30.87441 8.224995e-126 2.270099e-123
## hsa-mir-3613  2.199074  3.862900  23.32209  5.152888e-86  9.481314e-84
## hsa-mir-15a   1.335460  7.014647  22.83389  2.008313e-83  2.771472e-81
## hsa-mir-934  -3.234590 -1.930201 -22.39709  4.148098e-81  4.579500e-79
## hsa-mir-122   5.554068  3.112250  22.33183  9.192713e-81  8.457296e-79
##                     B change
## hsa-mir-141  280.9396   DOWN
## hsa-mir-200c 276.7881   DOWN
## hsa-mir-3613 185.4023     UP
## hsa-mir-15a  179.4222     UP
## hsa-mir-934  174.1455   DOWN
## hsa-mir-122  173.3486     UP
```

```r
limma_voom_DEG <- DEG
#save(DESeq2_DEG,edgeR_DEG,limma_voom_DEG,group_list,file = "DEG.Rdata")
```

### 4.差异分析结果的可视化

```r
rm(list = ls())
load("tcga_kirc_exp.Rdata")
load("DEG.Rdata")
source("3-plotfunction.R")
logFC_cutoff <- 1
expr[1:4,1:4]
```

```
##              TCGA-A3-3307-01A-01T-0860-13 TCGA-A3-3308-01A-02R-1324-13
## hsa-let-7a-1                         5056                        14503
## hsa-let-7a-2                        10323                        29238
## hsa-let-7a-3                         5429                        14738
## hsa-let-7b                          17908                        37062
##              TCGA-A3-3311-01A-02R-1324-13 TCGA-A3-3313-01A-02R-1324-13
## hsa-let-7a-1                         8147                         7138
## hsa-let-7a-2                        16325                        14356
## hsa-let-7a-3                         8249                         7002
## hsa-let-7b                          28984                         6909
```

```r
dat = log(expr+1)
pca.plot = draw_pca(dat,group_list)

cg1 = rownames(DESeq2_DEG)[DESeq2_DEG$change !="NOT"]
cg2 = rownames(edgeR_DEG)[edgeR_DEG$change !="NOT"]
cg3 = rownames(limma_voom_DEG)[limma_voom_DEG$change !="NOT"]

h1 = draw_heatmap(expr[cg1,],group_list)
h2 = draw_heatmap(expr[cg2,],group_list)
h3 = draw_heatmap(expr[cg3,],group_list)
```

```r
v1 = draw_volcano(test = DESeq2_DEG[,c(2,5,7)],pkg = 1)
v2 = draw_volcano(test = edgeR_DEG[,c(1,4,6)],pkg = 2)
v3 = draw_volcano(test = limma_voom_DEG[,c(1,4,7)],pkg = 3)

library(patchwork)
(h1 + h2 + h3) / (v1 + v2 + v3) +plot_layout(guides = 'collect')
```

![](https://upload-images.jianshu.io/upload_images/9475888-20f5537a31c7f231.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

```r
#(v1 + v2 + v3) +plot_layout(guides = 'collect')
ggsave("heat_volcano.png",width = 21,height = 9)
```

### 5.三大R包差异基因对比


```r
# 三大R包差异基因交集
UP=function(df){
  rownames(df)[df$change=="UP"]
}
DOWN=function(df){
  rownames(df)[df$change=="DOWN"]
}

up = intersect(intersect(UP(DESeq2_DEG),UP(edgeR_DEG)),UP(limma_voom_DEG))
down = intersect(intersect(DOWN(DESeq2_DEG),DOWN(edgeR_DEG)),DOWN(limma_voom_DEG))

hp = draw_heatmap(expr[c(up,down),],group_list)

#上调、下调基因分别画维恩图

up.plot <- venn(UP(DESeq2_DEG),UP(edgeR_DEG),UP(limma_voom_DEG),
                "UPgene"
)
```

```r
down.plot <- venn(DOWN(DESeq2_DEG),DOWN(edgeR_DEG),DOWN(limma_voom_DEG),
                  "DOWNgene"
)
#维恩图拼图，终于搞定

library(cowplot)
library(ggplotify)
up.plot = as.ggplot(as_grob(up.plot))
down.plot = as.ggplot(as_grob(down.plot))
library(patchwork)
#up.plot + down.plot
```

```r
# 就爱玩拼图
pca.plot + hp+up.plot +down.plot
```

```r
ggsave("deg.png",height = 10,width = 10)
```

![](https://upload-images.jianshu.io/upload_images/9475888-07be4b7fe2a97e79.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

三个R包差异分析结果的交集共有50个上调和51个下调，可以作为最终结果提交。当然，这三个包没有对错之分，你拿其中任意一个包的分析结果都是对的。取交集的方法更可靠，但不是必须的，有些数据取交集会很可怜的。

