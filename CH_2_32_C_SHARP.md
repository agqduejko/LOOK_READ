### C#程式說明

C#程式寫法：

---
//主程式-MAIN()
> 藍圖-老闆C 老闆3號 = new 藍圖-老闆C();	//依藍圖，做出【老闆3號】  
> 老闆3號.秀到-LOG = 秀到-LOG;		//■在主程式用	//■3-只讓它連結一次  
> }//主程式-MAIN--結束

//主程式-功能-秀到-LOG
> public void 秀到-LOG(string 字串){  
> TXB-LOG.AppendText("\r\n"+字串);  
> }//秀到-LOG()--結束

---
//藍圖-老闆C

```
public class 藍圖-老闆C {  
public int 現金=0;  
public int 能拿出的現金=0;  
public string 顯示="";//顯示用  
public delegate void 老闆-秀到-LOG(string AA);	//■1-宣告委派  
public 老闆-秀到-LOG 秀到-LOG;					//■2-把這個委派產生成物件  
//老闆3號.秀到-LOG = 秀到-LOG;	//■在主程式用	//■3-只讓它連結一次
```

//功能1-給他現金
```
public void 給他現金(int 給現金){  
現金+=給現金;  
顯示="拿到 " +給現金.ToString()+ " ，現在有 "+現金.ToString();  
秀到-LOG(顯示);  
}//給他現金()--結束
```

//功能2-拿出現金
```
public void 叫他拿出來(int 拿出來){
//--------------------------------
//錢 夠 的話
//--------------------------------
if (現金 >= 拿出來) {
現金-=拿出來;
顯示="原本 = "+(現金 + 拿出來).ToString();
顯示+=" - 拿出來 "+拿出來.ToString();
顯示+=" = 剩下 "+現金.ToString();
}//if()--結束
//--------------------------------
//錢 不夠 的話
//--------------------------------
else {
顯示="只剩 " + 現金.ToString();
顯示+=" 拿不出 " + 拿出來.ToString();
}//ELSE()--結束
//--------------------------------
//顯示
//--------------------------------
秀到-LOG(顯示);
秀到-A現金(現金);
}//叫他拿出來()--結束

}//CLASS-藍圖-C老闆()--結束
```


