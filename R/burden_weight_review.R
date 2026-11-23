review_weighted_burden <- function(x,weights) {
  w<-unlist(weights)
  stopifnot(length(w)>0,!is.null(names(w)),!anyDuplicated(names(w)),all(names(w)%in%names(x)),
    all(is.finite(w)),all(w>=0),sum(w)>0)
  w<-w[w>0];w<-w/sum(w)
  m<-as.matrix(x[,names(w),drop=FALSE]);valid<-apply(is.finite(m),1,all)
  if(any(m<0|m>100,na.rm=TRUE))stop('Domain score outside [0,100]')
  out<-rep(NA_real_,nrow(x));out[valid]<-as.numeric(m[valid,,drop=FALSE]%*%w)
  out
}
review_burden_warning <- function(flags) {
  m<-as.matrix(flags)
  high<-rowSums(m==TRUE,na.rm=TRUE)>0
  complete<-rowSums(is.na(m))==0
  data.frame(any_high=ifelse(high,TRUE,ifelse(complete,FALSE,NA)),
    assessment_complete=complete,
    warning_status=ifelse(high,ifelse(complete,'High burden identified','High burden identified; incomplete assessment'),
      ifelse(complete,'No high-burden flags identified','Incomplete assessment')))
}
