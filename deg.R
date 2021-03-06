rm(list = ls())
#### 1.准备R包
if(!require(stringr))install.packages('stringr')
if(!require(ggplotify))install.packages("ggplotify")
if(!require(patchwork))install.packages("patchwork")
if(!require(cowplot))install.packages("cowplot")
if(!require(DESeq2))install.packages('DESeq2')
if(!require(edgeR))install.packages('edgeR')
if(!require(limma))install.packages('limma')

#### 2.准备数据
load("tcga_kirc_exp.Rdata") #表达矩阵expr
dim(expr)
group_list <- ifelse(as.numeric(str_sub(colnames(expr),14,15))<10,"tumor","normal")
group_list <- factor(group_list,levels = c("normal","tumor"))
table(group_list)
#### 3.三大R包的差异分析
#deseq2----

library(DESeq2)
#需修改results()的contrast参数
#输入：表达矩阵和分组信息
#输出：差异分析结果、火山图
#构建colData (condition存在于colData中，是表示分组的因子型变量)
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
#edgeR----
library(edgeR)

dge <- DGEList(counts=expr,group=group_list)
dge$samples$lib.size <- colSums(dge$counts)
dge$samples
dge <- calcNormFactors(dge) 
dge$samples

design <- model.matrix(~0+group_list)
rownames(design)<-colnames(dge)
colnames(design)<-levels(group_list)

dge <- estimateGLMCommonDisp(dge,design)
dge <- estimateGLMTrendedDisp(dge, design)
dge <- estimateGLMTagwiseDisp(dge, design)

fit <- glmFit(dge, design)
fit2 <- glmLRT(fit, contrast=c(-1,1)) #需要根据design修改contrast

DEG=topTags(fit2, n=nrow(expr))
DEG=as.data.frame(DEG)
logFC_cutoff <- with(DEG,mean(abs(logFC)) + 2*sd(abs(logFC)) )
logFC_cutoff <- 1
DEG$change = as.factor(
  ifelse(DEG$PValue < 0.05 & abs(DEG$logFC) > logFC_cutoff,
         ifelse(DEG$logFC > logFC_cutoff ,'UP','DOWN'),'NOT')
)
head(DEG)

table(DEG$change)
edgeR_DEG <- DEG
#limma----

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
limma_voom_DEG <- DEG
save(DESeq2_DEG,edgeR_DEG,limma_voom_DEG,group_list,file = "DEG.Rdata")
#----
#### 4.差异分析结果的可视化
#plots----
rm(list = ls())
load("tcga_kirc_exp.Rdata")
load("DEG.Rdata")
source("3-plotfunction.R")
logFC_cutoff <- 1
expr[1:4,1:4]
dat = log(expr+1)
pca.plot = draw_pca(dat,group_list)

cg1 = rownames(DESeq2_DEG)[DESeq2_DEG$change !="NOT"]
cg2 = rownames(edgeR_DEG)[edgeR_DEG$change !="NOT"]
cg3 = rownames(limma_voom_DEG)[limma_voom_DEG$change !="NOT"]

h1 = draw_heatmap(expr[cg1,],group_list)
h2 = draw_heatmap(expr[cg2,],group_list)
h3 = draw_heatmap(expr[cg3,],group_list)

v1 = draw_volcano(test = DESeq2_DEG[,c(2,5,7)],pkg = 1)
v2 = draw_volcano(test = edgeR_DEG[,c(1,4,6)],pkg = 2)
v3 = draw_volcano(test = limma_voom_DEG[,c(1,4,7)],pkg = 3)

library(patchwork)
(h1 + h2 + h3) / (v1 + v2 + v3) +plot_layout(guides = 'collect')
#(v1 + v2 + v3) +plot_layout(guides = 'collect')
ggsave("heat_volcano.png",width = 21,height = 9)

#5.三大R包差异基因对比----
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
down.plot <- venn(DOWN(DESeq2_DEG),DOWN(edgeR_DEG),DOWN(limma_voom_DEG),
                  "DOWNgene"
)

#维恩图拼图，终于搞定

library(cowplot)
library(ggplotify)
up.plot = as.ggplot(as_grob(up.plot))
down.plot = as.ggplot(as_grob(down.plot))
library(patchwork)
up.plot + down.plot

# 就爱玩拼图

pca.plot + hp+up.plot +down.plot

ggsave("deg.png",height = 10,width = 10)

