; ModuleID = 'files.ll'
source_filename = "zs_module"

%Either__FsError_String = type { i32, { i32, i64 } }
%FsError = type { i32 }
%Either__FsError_number = type { i32, %FsError }

define void @init() local_unnamed_addr {
entry:
  %strVal = alloca [10 x i8], align 1
  store i8 46, ptr %strVal, align 1
  %.fca.1.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 1
  store i8 47, ptr %.fca.1.gep, align 1
  %.fca.2.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 2
  store i8 102, ptr %.fca.2.gep, align 1
  %.fca.3.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 3
  store i8 105, ptr %.fca.3.gep, align 1
  %.fca.4.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 4
  store i8 108, ptr %.fca.4.gep, align 1
  %.fca.5.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 5
  store i8 101, ptr %.fca.5.gep, align 1
  %.fca.6.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 6
  store i8 115, ptr %.fca.6.gep, align 1
  %.fca.7.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 7
  store i8 46, ptr %.fca.7.gep, align 1
  %.fca.8.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 8
  store i8 122, ptr %.fca.8.gep, align 1
  %.fca.9.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 9
  store i8 115, ptr %.fca.9.gep, align 1
  %strptrint = ptrtoint ptr %strVal to i64
  %arg.fca.1.insert = insertvalue { i32, i64 } { i32 10, i64 undef }, i64 %strptrint, 1
  %call_result = call %Either__FsError_String @readFile({ i32, i64 } %arg.fca.1.insert)
  %call_result.fca.0.extract = extractvalue %Either__FsError_String %call_result, 0
  %switch = icmp eq i32 %call_result.fca.0.extract, 1
  br i1 %switch, label %arm_1, label %arm_0

match_end:                                        ; preds = %arm_0, %print__String.exit
  ret void

arm_1:                                            ; preds = %entry
  %arm_payload = extractvalue %Either__FsError_String %call_result, 1
  %.fca.0.extract.i = extractvalue { i32, i64 } %arm_payload, 0
  %add.i = add i32 %.fca.0.extract.i, 1
  %argext.i = sext i32 %add.i to i64
  %asmres.i.i = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext.i, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp15.i = icmp sgt i32 %.fca.0.extract.i, 0
  br i1 %cmp15.i, label %while.body.lr.ph.i, label %print__String.exit

while.body.lr.ph.i:                               ; preds = %arm_1
  %.fca.1.extract.i.i = extractvalue { i32, i64 } %arm_payload, 1
  br label %while.body.i

while.body.i:                                     ; preds = %while.body.i, %while.body.lr.ph.i
  %x12.016.i = phi i32 [ 0, %while.body.lr.ph.i ], [ %add25.i, %while.body.i ]
  %idx64.i.i = zext nneg i32 %x12.016.i to i64
  %ptradd.i.i = add i64 %.fca.1.extract.i.i, %idx64.i.i
  %typedptr.i.i = inttoptr i64 %ptradd.i.i to ptr
  %typedval.i.i = load i8, ptr %typedptr.i.i, align 1
  %ptradd.i = add i64 %asmres.i.i, %idx64.i.i
  %typedptr.i = inttoptr i64 %ptradd.i to ptr
  store i8 %typedval.i.i, ptr %typedptr.i, align 1
  %add25.i = add nuw nsw i32 %x12.016.i, 1
  %cmp.i = icmp slt i32 %add25.i, %.fca.0.extract.i
  br i1 %cmp.i, label %while.body.i, label %print__String.exit

print__String.exit:                               ; preds = %while.body.i, %arm_1
  %idx6433.i = sext i32 %.fca.0.extract.i to i64
  %ptradd35.i = add i64 %asmres.i.i, %idx6433.i
  %typedptr36.i = inttoptr i64 %ptradd35.i to ptr
  store i8 10, ptr %typedptr36.i, align 1
  call void asm sideeffect "syscall", "{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 1, i64 1, i64 %asmres.i.i, i64 %argext.i) #6
  call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %asmres.i.i, i64 %argext.i) #6
  br label %match_end

arm_0:                                            ; preds = %entry
  %strVal14 = alloca [18 x i8], align 1
  store i8 101, ptr %strVal14, align 1
  %strVal14.repack4 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 1
  store i8 114, ptr %strVal14.repack4, align 1
  %strVal14.repack5 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 2
  store i8 114, ptr %strVal14.repack5, align 1
  %strVal14.repack6 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 3
  store i8 111, ptr %strVal14.repack6, align 1
  %strVal14.repack7 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 4
  store i8 114, ptr %strVal14.repack7, align 1
  %strVal14.repack8 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 5
  store i8 32, ptr %strVal14.repack8, align 1
  %strVal14.repack9 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 6
  store i8 114, ptr %strVal14.repack9, align 1
  %strVal14.repack10 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 7
  store i8 101, ptr %strVal14.repack10, align 1
  %strVal14.repack11 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 8
  store i8 97, ptr %strVal14.repack11, align 1
  %strVal14.repack12 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 9
  store i8 100, ptr %strVal14.repack12, align 1
  %strVal14.repack13 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 10
  store i8 105, ptr %strVal14.repack13, align 1
  %strVal14.repack14 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 11
  store i8 110, ptr %strVal14.repack14, align 1
  %strVal14.repack15 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 12
  store i8 103, ptr %strVal14.repack15, align 1
  %strVal14.repack16 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 13
  store i8 32, ptr %strVal14.repack16, align 1
  %strVal14.repack17 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 14
  store i8 102, ptr %strVal14.repack17, align 1
  %strVal14.repack18 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 15
  store i8 105, ptr %strVal14.repack18, align 1
  %strVal14.repack19 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 16
  store i8 108, ptr %strVal14.repack19, align 1
  %strVal14.repack20 = getelementptr inbounds [18 x i8], ptr %strVal14, i64 0, i64 17
  store i8 101, ptr %strVal14.repack20, align 1
  %strptrint15 = ptrtoint ptr %strVal14 to i64
  %asmres.i.i24 = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 19, i64 3, i64 34, i64 -1, i64 0) #6
  %typedval.i.i35 = load i8, ptr %strVal14, align 1
  %typedptr.i37 = inttoptr i64 %asmres.i.i24 to ptr
  store i8 %typedval.i.i35, ptr %typedptr.i37, align 1
  %ptradd.i.i33.1 = add i64 %strptrint15, 1
  %typedptr.i.i34.1 = inttoptr i64 %ptradd.i.i33.1 to ptr
  %typedval.i.i35.1 = load i8, ptr %typedptr.i.i34.1, align 1
  %ptradd.i36.1 = add i64 %asmres.i.i24, 1
  %typedptr.i37.1 = inttoptr i64 %ptradd.i36.1 to ptr
  store i8 %typedval.i.i35.1, ptr %typedptr.i37.1, align 1
  %ptradd.i.i33.2 = add i64 %strptrint15, 2
  %typedptr.i.i34.2 = inttoptr i64 %ptradd.i.i33.2 to ptr
  %typedval.i.i35.2 = load i8, ptr %typedptr.i.i34.2, align 1
  %ptradd.i36.2 = add i64 %asmres.i.i24, 2
  %typedptr.i37.2 = inttoptr i64 %ptradd.i36.2 to ptr
  store i8 %typedval.i.i35.2, ptr %typedptr.i37.2, align 1
  %ptradd.i.i33.3 = add i64 %strptrint15, 3
  %typedptr.i.i34.3 = inttoptr i64 %ptradd.i.i33.3 to ptr
  %typedval.i.i35.3 = load i8, ptr %typedptr.i.i34.3, align 1
  %ptradd.i36.3 = add i64 %asmres.i.i24, 3
  %typedptr.i37.3 = inttoptr i64 %ptradd.i36.3 to ptr
  store i8 %typedval.i.i35.3, ptr %typedptr.i37.3, align 1
  %ptradd.i.i33.4 = add i64 %strptrint15, 4
  %typedptr.i.i34.4 = inttoptr i64 %ptradd.i.i33.4 to ptr
  %typedval.i.i35.4 = load i8, ptr %typedptr.i.i34.4, align 1
  %ptradd.i36.4 = add i64 %asmres.i.i24, 4
  %typedptr.i37.4 = inttoptr i64 %ptradd.i36.4 to ptr
  store i8 %typedval.i.i35.4, ptr %typedptr.i37.4, align 1
  %ptradd.i.i33.5 = add i64 %strptrint15, 5
  %typedptr.i.i34.5 = inttoptr i64 %ptradd.i.i33.5 to ptr
  %typedval.i.i35.5 = load i8, ptr %typedptr.i.i34.5, align 1
  %ptradd.i36.5 = add i64 %asmres.i.i24, 5
  %typedptr.i37.5 = inttoptr i64 %ptradd.i36.5 to ptr
  store i8 %typedval.i.i35.5, ptr %typedptr.i37.5, align 1
  %ptradd.i.i33.6 = add i64 %strptrint15, 6
  %typedptr.i.i34.6 = inttoptr i64 %ptradd.i.i33.6 to ptr
  %typedval.i.i35.6 = load i8, ptr %typedptr.i.i34.6, align 1
  %ptradd.i36.6 = add i64 %asmres.i.i24, 6
  %typedptr.i37.6 = inttoptr i64 %ptradd.i36.6 to ptr
  store i8 %typedval.i.i35.6, ptr %typedptr.i37.6, align 1
  %ptradd.i.i33.7 = add i64 %strptrint15, 7
  %typedptr.i.i34.7 = inttoptr i64 %ptradd.i.i33.7 to ptr
  %typedval.i.i35.7 = load i8, ptr %typedptr.i.i34.7, align 1
  %ptradd.i36.7 = add i64 %asmres.i.i24, 7
  %typedptr.i37.7 = inttoptr i64 %ptradd.i36.7 to ptr
  store i8 %typedval.i.i35.7, ptr %typedptr.i37.7, align 1
  %ptradd.i.i33.8 = add i64 %strptrint15, 8
  %typedptr.i.i34.8 = inttoptr i64 %ptradd.i.i33.8 to ptr
  %typedval.i.i35.8 = load i8, ptr %typedptr.i.i34.8, align 1
  %ptradd.i36.8 = add i64 %asmres.i.i24, 8
  %typedptr.i37.8 = inttoptr i64 %ptradd.i36.8 to ptr
  store i8 %typedval.i.i35.8, ptr %typedptr.i37.8, align 1
  %ptradd.i.i33.9 = add i64 %strptrint15, 9
  %typedptr.i.i34.9 = inttoptr i64 %ptradd.i.i33.9 to ptr
  %typedval.i.i35.9 = load i8, ptr %typedptr.i.i34.9, align 1
  %ptradd.i36.9 = add i64 %asmres.i.i24, 9
  %typedptr.i37.9 = inttoptr i64 %ptradd.i36.9 to ptr
  store i8 %typedval.i.i35.9, ptr %typedptr.i37.9, align 1
  %ptradd.i.i33.10 = add i64 %strptrint15, 10
  %typedptr.i.i34.10 = inttoptr i64 %ptradd.i.i33.10 to ptr
  %typedval.i.i35.10 = load i8, ptr %typedptr.i.i34.10, align 1
  %ptradd.i36.10 = add i64 %asmres.i.i24, 10
  %typedptr.i37.10 = inttoptr i64 %ptradd.i36.10 to ptr
  store i8 %typedval.i.i35.10, ptr %typedptr.i37.10, align 1
  %ptradd.i.i33.11 = add i64 %strptrint15, 11
  %typedptr.i.i34.11 = inttoptr i64 %ptradd.i.i33.11 to ptr
  %typedval.i.i35.11 = load i8, ptr %typedptr.i.i34.11, align 1
  %ptradd.i36.11 = add i64 %asmres.i.i24, 11
  %typedptr.i37.11 = inttoptr i64 %ptradd.i36.11 to ptr
  store i8 %typedval.i.i35.11, ptr %typedptr.i37.11, align 1
  %ptradd.i.i33.12 = add i64 %strptrint15, 12
  %typedptr.i.i34.12 = inttoptr i64 %ptradd.i.i33.12 to ptr
  %typedval.i.i35.12 = load i8, ptr %typedptr.i.i34.12, align 1
  %ptradd.i36.12 = add i64 %asmres.i.i24, 12
  %typedptr.i37.12 = inttoptr i64 %ptradd.i36.12 to ptr
  store i8 %typedval.i.i35.12, ptr %typedptr.i37.12, align 1
  %ptradd.i.i33.13 = add i64 %strptrint15, 13
  %typedptr.i.i34.13 = inttoptr i64 %ptradd.i.i33.13 to ptr
  %typedval.i.i35.13 = load i8, ptr %typedptr.i.i34.13, align 1
  %ptradd.i36.13 = add i64 %asmres.i.i24, 13
  %typedptr.i37.13 = inttoptr i64 %ptradd.i36.13 to ptr
  store i8 %typedval.i.i35.13, ptr %typedptr.i37.13, align 1
  %ptradd.i.i33.14 = add i64 %strptrint15, 14
  %typedptr.i.i34.14 = inttoptr i64 %ptradd.i.i33.14 to ptr
  %typedval.i.i35.14 = load i8, ptr %typedptr.i.i34.14, align 1
  %ptradd.i36.14 = add i64 %asmres.i.i24, 14
  %typedptr.i37.14 = inttoptr i64 %ptradd.i36.14 to ptr
  store i8 %typedval.i.i35.14, ptr %typedptr.i37.14, align 1
  %ptradd.i.i33.15 = add i64 %strptrint15, 15
  %typedptr.i.i34.15 = inttoptr i64 %ptradd.i.i33.15 to ptr
  %typedval.i.i35.15 = load i8, ptr %typedptr.i.i34.15, align 1
  %ptradd.i36.15 = add i64 %asmres.i.i24, 15
  %typedptr.i37.15 = inttoptr i64 %ptradd.i36.15 to ptr
  store i8 %typedval.i.i35.15, ptr %typedptr.i37.15, align 1
  %ptradd.i.i33.16 = add i64 %strptrint15, 16
  %typedptr.i.i34.16 = inttoptr i64 %ptradd.i.i33.16 to ptr
  %typedval.i.i35.16 = load i8, ptr %typedptr.i.i34.16, align 1
  %ptradd.i36.16 = add i64 %asmres.i.i24, 16
  %typedptr.i37.16 = inttoptr i64 %ptradd.i36.16 to ptr
  store i8 %typedval.i.i35.16, ptr %typedptr.i37.16, align 1
  %ptradd.i.i33.17 = add i64 %strptrint15, 17
  %typedptr.i.i34.17 = inttoptr i64 %ptradd.i.i33.17 to ptr
  %typedval.i.i35.17 = load i8, ptr %typedptr.i.i34.17, align 1
  %ptradd.i36.17 = add i64 %asmres.i.i24, 17
  %typedptr.i37.17 = inttoptr i64 %ptradd.i36.17 to ptr
  store i8 %typedval.i.i35.17, ptr %typedptr.i37.17, align 1
  %ptradd35.i27 = add i64 %asmres.i.i24, 18
  %typedptr36.i28 = inttoptr i64 %ptradd35.i27 to ptr
  store i8 10, ptr %typedptr36.i28, align 1
  call void asm sideeffect "syscall", "{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 1, i64 1, i64 %asmres.i.i24, i64 19) #6
  call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %asmres.i.i24, i64 19) #6
  br label %match_end
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define %FsError @errnoToFsError(i32 %0) local_unnamed_addr #0 {
entry:
  switch i32 %0, label %match_end [
    i32 2, label %arm_0
    i32 9, label %arm_013
    i32 13, label %arm_016
    i32 28, label %arm_019
  ]

match_end:                                        ; preds = %entry, %arm_019, %arm_016, %arm_013, %arm_0
  %matchresult = phi %FsError [ zeroinitializer, %arm_0 ], [ { i32 2 }, %arm_013 ], [ { i32 1 }, %arm_016 ], [ { i32 3 }, %arm_019 ], [ { i32 4 }, %entry ]
  ret %FsError %matchresult

arm_0:                                            ; preds = %entry
  br label %match_end

arm_013:                                          ; preds = %entry
  br label %match_end

arm_016:                                          ; preds = %entry
  br label %match_end

arm_019:                                          ; preds = %entry
  br label %match_end
}

define %Either__FsError_number @open({ i32, i64 } %0, i32 %1, i32 %2) local_unnamed_addr {
entry:
  %.fca.0.extract = extractvalue { i32, i64 } %0, 0
  %add.i = add i32 %.fca.0.extract, 1
  %argext.i = sext i32 %add.i to i64
  %asmres.i.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext.i, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp12.i = icmp sgt i32 %.fca.0.extract, 0
  br i1 %cmp12.i, label %while.body.lr.ph.i, label %toCstr.exit

while.body.lr.ph.i:                               ; preds = %entry
  %.fca.1.extract.i.i = extractvalue { i32, i64 } %0, 1
  br label %while.body.i

while.body.i:                                     ; preds = %while.body.i, %while.body.lr.ph.i
  %x12.013.i = phi i32 [ 0, %while.body.lr.ph.i ], [ %add25.i, %while.body.i ]
  %idx64.i.i = zext nneg i32 %x12.013.i to i64
  %ptradd.i.i = add i64 %.fca.1.extract.i.i, %idx64.i.i
  %typedptr.i.i = inttoptr i64 %ptradd.i.i to ptr
  %typedval.i.i = load i8, ptr %typedptr.i.i, align 1
  %ptradd.i = add i64 %asmres.i.i, %idx64.i.i
  %typedptr.i = inttoptr i64 %ptradd.i to ptr
  store i8 %typedval.i.i, ptr %typedptr.i, align 1
  %add25.i = add nuw nsw i32 %x12.013.i, 1
  %cmp.i = icmp slt i32 %add25.i, %.fca.0.extract
  br i1 %cmp.i, label %while.body.i, label %toCstr.exit

toCstr.exit:                                      ; preds = %while.body.i, %entry
  %idx6433.i = sext i32 %.fca.0.extract to i64
  %ptradd35.i = add i64 %asmres.i.i, %idx6433.i
  %typedptr36.i = inttoptr i64 %ptradd35.i to ptr
  store i8 0, ptr %typedptr36.i, align 1
  %asmext14 = sext i32 %1 to i64
  %asmext16 = sext i32 %2 to i64
  %asmres = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 2, i64 %asmres.i.i, i64 %asmext14, i64 %asmext16) #6
  tail call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %asmres.i.i, i64 %argext.i) #6
  %cmp = icmp slt i64 %asmres, 0
  %3 = trunc i64 %asmres to i32
  br i1 %cmp, label %then, label %merge

common.ret:                                       ; preds = %arm_019.i, %arm_016.i, %arm_013.i, %arm_0.i, %then, %merge
  %.pn = phi %Either__FsError_number [ { i32 1, %FsError undef }, %merge ], [ { i32 0, %FsError undef }, %then ], [ { i32 0, %FsError undef }, %arm_0.i ], [ { i32 0, %FsError undef }, %arm_013.i ], [ { i32 0, %FsError undef }, %arm_016.i ], [ { i32 0, %FsError undef }, %arm_019.i ]
  %call_result28.pn = phi %FsError [ %pay_reint6, %merge ], [ { i32 4 }, %then ], [ zeroinitializer, %arm_0.i ], [ { i32 2 }, %arm_013.i ], [ { i32 1 }, %arm_016.i ], [ { i32 3 }, %arm_019.i ]
  %common.ret.op = insertvalue %Either__FsError_number %.pn, %FsError %call_result28.pn, 1
  ret %Either__FsError_number %common.ret.op

then:                                             ; preds = %toCstr.exit
  switch i32 %3, label %common.ret [
    i32 -2, label %arm_0.i
    i32 -9, label %arm_013.i
    i32 -13, label %arm_016.i
    i32 -28, label %arm_019.i
  ]

arm_0.i:                                          ; preds = %then
  br label %common.ret

arm_013.i:                                        ; preds = %then
  br label %common.ret

arm_016.i:                                        ; preds = %then
  br label %common.ret

arm_019.i:                                        ; preds = %then
  br label %common.ret

merge:                                            ; preds = %toCstr.exit
  %pay_reint6 = insertvalue %FsError poison, i32 %3, 0
  br label %common.ret
}

define void @close(i32 %0) local_unnamed_addr {
entry:
  %asmext13 = sext i32 %0 to i64
  tail call void asm sideeffect "syscall", "{rax},{rdi},~{rcx},~{r11},~{memory}"(i64 3, i64 %asmext13) #6
  ret void
}

define i32 @writeFd(i32 %0, { i32, i64 } %1) local_unnamed_addr {
entry:
  %.fca.0.extract = extractvalue { i32, i64 } %1, 0
  %.fca.1.extract = extractvalue { i32, i64 } %1, 1
  %asmext16 = sext i32 %0 to i64
  %asmext19 = sext i32 %.fca.0.extract to i64
  %asmres = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 1, i64 %asmext16, i64 %.fca.1.extract, i64 %asmext19) #6
  %retcoerce = trunc i64 %asmres to i32
  ret i32 %retcoerce
}

define i32 @readFd(i32 %0, i64 %1, i32 %2) local_unnamed_addr {
entry:
  %asmext13 = sext i32 %0 to i64
  %asmext16 = sext i32 %2 to i64
  %asmres = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 0, i64 %asmext13, i64 %1, i64 %asmext16) #6
  %retcoerce = trunc i64 %asmres to i32
  ret i32 %retcoerce
}

define %Either__FsError_String @readFile({ i32, i64 } %0) local_unnamed_addr {
entry:
  %strVal = alloca [10 x i8], align 1
  store i8 46, ptr %strVal, align 1
  %.fca.1.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 1
  store i8 47, ptr %.fca.1.gep, align 1
  %.fca.2.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 2
  store i8 102, ptr %.fca.2.gep, align 1
  %.fca.3.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 3
  store i8 105, ptr %.fca.3.gep, align 1
  %.fca.4.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 4
  store i8 108, ptr %.fca.4.gep, align 1
  %.fca.5.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 5
  store i8 101, ptr %.fca.5.gep, align 1
  %.fca.6.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 6
  store i8 115, ptr %.fca.6.gep, align 1
  %.fca.7.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 7
  store i8 46, ptr %.fca.7.gep, align 1
  %.fca.8.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 8
  store i8 122, ptr %.fca.8.gep, align 1
  %.fca.9.gep = getelementptr inbounds [10 x i8], ptr %strVal, i64 0, i64 9
  store i8 115, ptr %.fca.9.gep, align 1
  %strptrint = ptrtoint ptr %strVal to i64
  %arg12.fca.1.insert = insertvalue { i32, i64 } { i32 10, i64 undef }, i64 %strptrint, 1
  %call_result = call %Either__FsError_number @open({ i32, i64 } %0, { i32, i64 } %arg12.fca.1.insert, i32 0)
  %call_result.fca.0.extract = extractvalue %Either__FsError_number %call_result, 0
  %switch = icmp eq i32 %call_result.fca.0.extract, 0
  %arm_payload = extractvalue %Either__FsError_number %call_result, 1
  %1 = extractvalue %FsError %arm_payload, 0
  br i1 %switch, label %common.ret, label %arm_1

common.ret:                                       ; preds = %entry, %arm_019.i, %arm_016.i, %arm_013.i, %arm_0.i, %then, %arm_1
  %.pn = phi %Either__FsError_String [ { i32 1, { i32, i64 } undef }, %arm_1 ], [ { i32 0, { i32, i64 } undef }, %then ], [ { i32 0, { i32, i64 } undef }, %arm_0.i ], [ { i32 0, { i32, i64 } undef }, %arm_013.i ], [ { i32 0, { i32, i64 } undef }, %arm_016.i ], [ { i32 0, { i32, i64 } undef }, %arm_019.i ], [ { i32 0, { i32, i64 } undef }, %entry ]
  %.pn12 = phi i32 [ %retcoerce.i, %arm_1 ], [ 4, %then ], [ 0, %arm_0.i ], [ 2, %arm_013.i ], [ 1, %arm_016.i ], [ 3, %arm_019.i ], [ %1, %entry ]
  %.pn10 = phi i64 [ %asmres.i, %arm_1 ], [ 0, %then ], [ 0, %arm_0.i ], [ 0, %arm_013.i ], [ 0, %arm_016.i ], [ 0, %arm_019.i ], [ 0, %entry ]
  %.pn9 = insertvalue { i32, i64 } undef, i32 %.pn12, 0
  %pay_reint8.pn = insertvalue { i32, i64 } %.pn9, i64 %.pn10, 1
  %common.ret.op = insertvalue %Either__FsError_String %.pn, { i32, i64 } %pay_reint8.pn, 1
  ret %Either__FsError_String %common.ret.op

arm_1:                                            ; preds = %entry
  %asmres.i = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 65536, i64 3, i64 34, i64 -1, i64 0) #6
  %asmext13.i = sext i32 %1 to i64
  %asmres.i13 = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 0, i64 %asmext13.i, i64 %asmres.i, i64 65536) #6
  %retcoerce.i = trunc i64 %asmres.i13 to i32
  call void asm sideeffect "syscall", "{rax},{rdi},~{rcx},~{r11},~{memory}"(i64 3, i64 %asmext13.i) #6
  %cmp = icmp slt i32 %retcoerce.i, 0
  br i1 %cmp, label %then, label %common.ret

then:                                             ; preds = %arm_1
  call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %asmres.i, i64 65536) #6
  switch i32 %retcoerce.i, label %common.ret [
    i32 -2, label %arm_0.i
    i32 -9, label %arm_013.i
    i32 -13, label %arm_016.i
    i32 -28, label %arm_019.i
  ]

arm_0.i:                                          ; preds = %then
  br label %common.ret

arm_013.i:                                        ; preds = %then
  br label %common.ret

arm_016.i:                                        ; preds = %then
  br label %common.ret

arm_019.i:                                        ; preds = %then
  br label %common.ret
}

define %Either__FsError_number @writeFile({ i32, i64 } %0, { i32, i64 } %1) local_unnamed_addr {
entry:
  %.fca.0.extract.i = extractvalue { i32, i64 } %0, 0
  %add.i.i = add i32 %.fca.0.extract.i, 1
  %argext.i.i = sext i32 %add.i.i to i64
  %asmres.i.i.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext.i.i, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp12.i.i = icmp sgt i32 %.fca.0.extract.i, 0
  br i1 %cmp12.i.i, label %while.body.lr.ph.i.i, label %toCstr.exit.i

while.body.lr.ph.i.i:                             ; preds = %entry
  %.fca.1.extract.i.i.i = extractvalue { i32, i64 } %0, 1
  br label %while.body.i.i

while.body.i.i:                                   ; preds = %while.body.i.i, %while.body.lr.ph.i.i
  %x12.013.i.i = phi i32 [ 0, %while.body.lr.ph.i.i ], [ %add25.i.i, %while.body.i.i ]
  %idx64.i.i.i = zext nneg i32 %x12.013.i.i to i64
  %ptradd.i.i.i = add i64 %.fca.1.extract.i.i.i, %idx64.i.i.i
  %typedptr.i.i.i = inttoptr i64 %ptradd.i.i.i to ptr
  %typedval.i.i.i = load i8, ptr %typedptr.i.i.i, align 1
  %ptradd.i.i = add i64 %asmres.i.i.i, %idx64.i.i.i
  %typedptr.i.i = inttoptr i64 %ptradd.i.i to ptr
  store i8 %typedval.i.i.i, ptr %typedptr.i.i, align 1
  %add25.i.i = add nuw nsw i32 %x12.013.i.i, 1
  %cmp.i.i = icmp slt i32 %add25.i.i, %.fca.0.extract.i
  br i1 %cmp.i.i, label %while.body.i.i, label %toCstr.exit.i

toCstr.exit.i:                                    ; preds = %while.body.i.i, %entry
  %idx6433.i.i = sext i32 %.fca.0.extract.i to i64
  %ptradd35.i.i = add i64 %asmres.i.i.i, %idx6433.i.i
  %typedptr36.i.i = inttoptr i64 %ptradd35.i.i to ptr
  store i8 0, ptr %typedptr36.i.i, align 1
  %asmres.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 2, i64 %asmres.i.i.i, i64 577, i64 420) #6
  tail call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %asmres.i.i.i, i64 %argext.i.i) #6
  %cmp.i = icmp slt i64 %asmres.i, 0
  %2 = trunc i64 %asmres.i to i32
  br i1 %cmp.i, label %then.i, label %arm_1

then.i:                                           ; preds = %toCstr.exit.i
  switch i32 %2, label %common.ret [
    i32 -2, label %arm_0.i.i
    i32 -9, label %arm_013.i.i
    i32 -13, label %arm_016.i.i
    i32 -28, label %arm_019.i.i
  ]

arm_0.i.i:                                        ; preds = %then.i
  br label %common.ret

arm_013.i.i:                                      ; preds = %then.i
  br label %common.ret

arm_016.i.i:                                      ; preds = %then.i
  br label %common.ret

arm_019.i.i:                                      ; preds = %then.i
  br label %common.ret

common.ret:                                       ; preds = %arm_019.i.i, %arm_016.i.i, %arm_013.i.i, %arm_0.i.i, %then.i, %arm_019.i, %arm_016.i, %arm_013.i, %arm_0.i, %then, %merge
  %.pn = phi %Either__FsError_number [ { i32 1, %FsError undef }, %merge ], [ { i32 0, %FsError undef }, %then ], [ { i32 0, %FsError undef }, %arm_0.i ], [ { i32 0, %FsError undef }, %arm_013.i ], [ { i32 0, %FsError undef }, %arm_016.i ], [ { i32 0, %FsError undef }, %arm_019.i ], [ { i32 0, %FsError undef }, %then.i ], [ { i32 0, %FsError undef }, %arm_0.i.i ], [ { i32 0, %FsError undef }, %arm_013.i.i ], [ { i32 0, %FsError undef }, %arm_016.i.i ], [ { i32 0, %FsError undef }, %arm_019.i.i ]
  %arm_payload.pn = phi %FsError [ %pay_reint3, %merge ], [ { i32 4 }, %then ], [ zeroinitializer, %arm_0.i ], [ { i32 2 }, %arm_013.i ], [ { i32 1 }, %arm_016.i ], [ { i32 3 }, %arm_019.i ], [ { i32 4 }, %then.i ], [ zeroinitializer, %arm_0.i.i ], [ { i32 2 }, %arm_013.i.i ], [ { i32 1 }, %arm_016.i.i ], [ { i32 3 }, %arm_019.i.i ]
  %common.ret.op = insertvalue %Either__FsError_number %.pn, %FsError %arm_payload.pn, 1
  ret %Either__FsError_number %common.ret.op

arm_1:                                            ; preds = %toCstr.exit.i
  %.fca.0.extract.i4 = extractvalue { i32, i64 } %1, 0
  %.fca.1.extract.i = extractvalue { i32, i64 } %1, 1
  %asmext16.i = sext i32 %2 to i64
  %asmext19.i = sext i32 %.fca.0.extract.i4 to i64
  %asmres.i5 = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 1, i64 %asmext16.i, i64 %.fca.1.extract.i, i64 %asmext19.i) #6
  %retcoerce.i = trunc i64 %asmres.i5 to i32
  tail call void asm sideeffect "syscall", "{rax},{rdi},~{rcx},~{r11},~{memory}"(i64 3, i64 %asmext16.i) #6
  %cmp = icmp slt i32 %retcoerce.i, 0
  br i1 %cmp, label %then, label %merge

then:                                             ; preds = %arm_1
  switch i32 %retcoerce.i, label %common.ret [
    i32 -2, label %arm_0.i
    i32 -9, label %arm_013.i
    i32 -13, label %arm_016.i
    i32 -28, label %arm_019.i
  ]

arm_0.i:                                          ; preds = %then
  br label %common.ret

arm_013.i:                                        ; preds = %then
  br label %common.ret

arm_016.i:                                        ; preds = %then
  br label %common.ret

arm_019.i:                                        ; preds = %then
  br label %common.ret

merge:                                            ; preds = %arm_1
  %pay_reint3 = insertvalue %FsError poison, i32 %retcoerce.i, 0
  br label %common.ret
}

define void @print__String({ i32, i64 } %0) local_unnamed_addr {
entry:
  %.fca.0.extract = extractvalue { i32, i64 } %0, 0
  %add = add i32 %.fca.0.extract, 1
  %argext = sext i32 %add to i64
  %asmres.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp15 = icmp sgt i32 %.fca.0.extract, 0
  br i1 %cmp15, label %while.body.lr.ph, label %while.after

while.body.lr.ph:                                 ; preds = %entry
  %.fca.1.extract.i = extractvalue { i32, i64 } %0, 1
  br label %while.body

while.body:                                       ; preds = %while.body.lr.ph, %while.body
  %x12.016 = phi i32 [ 0, %while.body.lr.ph ], [ %add25, %while.body ]
  %idx64.i = zext nneg i32 %x12.016 to i64
  %ptradd.i = add i64 %.fca.1.extract.i, %idx64.i
  %typedptr.i = inttoptr i64 %ptradd.i to ptr
  %typedval.i = load i8, ptr %typedptr.i, align 1
  %ptradd = add i64 %asmres.i, %idx64.i
  %typedptr = inttoptr i64 %ptradd to ptr
  store i8 %typedval.i, ptr %typedptr, align 1
  %add25 = add nuw nsw i32 %x12.016, 1
  %cmp = icmp slt i32 %add25, %.fca.0.extract
  br i1 %cmp, label %while.body, label %while.after

while.after:                                      ; preds = %while.body, %entry
  %idx6433 = sext i32 %.fca.0.extract to i64
  %ptradd35 = add i64 %asmres.i, %idx6433
  %typedptr36 = inttoptr i64 %ptradd35 to ptr
  store i8 10, ptr %typedptr36, align 1
  tail call void asm sideeffect "syscall", "{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 1, i64 1, i64 %asmres.i, i64 %argext) #6
  tail call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %asmres.i, i64 %argext) #6
  ret void
}

define { i32, i64 } @numberToString(i32 %0) local_unnamed_addr {
entry:
  %arr = alloca [20 x i8], align 1
  %gep68 = getelementptr inbounds [20 x i8], ptr %arr, i64 0, i64 19
  %cmp = icmp slt i32 %0, 0
  %spec.select = tail call i32 @llvm.abs.i32(i32 %0, i1 false)
  %cmp80 = icmp eq i32 %0, 0
  %spec.store.select = select i1 %cmp80, i8 48, i8 0
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(19) %arr, i8 0, i64 19, i1 false)
  store i8 %spec.store.select, ptr %gep68, align 1
  %spec.select12 = select i1 %cmp80, i32 18, i32 19
  %cmp9713 = icmp sgt i32 %spec.select, 0
  br i1 %cmp9713, label %while.body, label %while.after

while.body:                                       ; preds = %entry, %while.body
  %n.115 = phi i32 [ %div, %while.body ], [ %spec.select, %entry ]
  %x69.114 = phi i32 [ %sub114, %while.body ], [ %spec.select12, %entry ]
  %n.115.frozen = freeze i32 %n.115
  %div = udiv i32 %n.115.frozen, 10
  %1 = mul i32 %div, 10
  %rem.decomposed = sub i32 %n.115.frozen, %1
  %2 = sext i32 %x69.114 to i64
  %stgep108 = getelementptr [20 x i8], ptr %arr, i64 0, i64 %2
  %3 = trunc i32 %rem.decomposed to i8
  %sttrunc110 = or disjoint i8 %3, 48
  store i8 %sttrunc110, ptr %stgep108, align 1
  %sub114 = add i32 %x69.114, -1
  %cmp97.not = icmp ult i32 %n.115, 10
  br i1 %cmp97.not, label %while.after, label %while.body

while.after:                                      ; preds = %while.body, %entry
  %x69.1.lcssa = phi i32 [ %spec.select12, %entry ], [ %sub114, %while.body ]
  br i1 %cmp, label %then129, label %merge131

then129:                                          ; preds = %while.after
  %4 = sext i32 %x69.1.lcssa to i64
  %stgep134 = getelementptr [20 x i8], ptr %arr, i64 0, i64 %4
  store i8 45, ptr %stgep134, align 1
  %sub140 = add i32 %x69.1.lcssa, -1
  br label %merge131

merge131:                                         ; preds = %while.after, %then129
  %x69.2 = phi i32 [ %sub140, %then129 ], [ %x69.1.lcssa, %while.after ]
  %add146 = add i32 %x69.2, 1
  %sub151 = sub i32 19, %x69.2
  %argext = sext i32 %sub151 to i64
  %asmres.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp15916 = icmp sgt i32 %sub151, 0
  br i1 %cmp15916, label %while.body155.preheader, label %while.after156

while.body155.preheader:                          ; preds = %merge131
  %min.iters.check = icmp ult i32 %sub151, 4
  %5 = add i32 %x69.2, 1
  %6 = icmp sgt i32 %5, 19
  %or.cond = or i1 %min.iters.check, %6
  br i1 %or.cond, label %while.body155.preheader19, label %vector.ph

vector.ph:                                        ; preds = %while.body155.preheader
  %n.vec = and i32 %sub151, 2147483644
  %broadcast.splatinsert = insertelement <4 x i64> poison, i64 %asmres.i, i64 0
  %broadcast.splat = shufflevector <4 x i64> %broadcast.splatinsert, <4 x i64> poison, <4 x i32> zeroinitializer
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i32 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %vec.ind = phi <4 x i32> [ <i32 0, i32 1, i32 2, i32 3>, %vector.ph ], [ %vec.ind.next, %vector.body ]
  %7 = add i32 %add146, %index
  %8 = sext i32 %7 to i64
  %9 = getelementptr [20 x i8], ptr %arr, i64 0, i64 %8
  %wide.load = load <4 x i8>, ptr %9, align 1
  %10 = zext <4 x i32> %vec.ind to <4 x i64>
  %11 = add <4 x i64> %broadcast.splat, %10
  %12 = inttoptr <4 x i64> %11 to <4 x ptr>
  %13 = extractelement <4 x i8> %wide.load, i64 0
  %14 = extractelement <4 x ptr> %12, i64 0
  store i8 %13, ptr %14, align 1
  %15 = extractelement <4 x i8> %wide.load, i64 1
  %16 = extractelement <4 x ptr> %12, i64 1
  store i8 %15, ptr %16, align 1
  %17 = extractelement <4 x i8> %wide.load, i64 2
  %18 = extractelement <4 x ptr> %12, i64 2
  store i8 %17, ptr %18, align 1
  %19 = extractelement <4 x i8> %wide.load, i64 3
  %20 = extractelement <4 x ptr> %12, i64 3
  store i8 %19, ptr %20, align 1
  %index.next = add nuw i32 %index, 4
  %vec.ind.next = add <4 x i32> %vec.ind, <i32 4, i32 4, i32 4, i32 4>
  %21 = icmp eq i32 %index.next, %n.vec
  br i1 %21, label %middle.block, label %vector.body, !llvm.loop !0

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i32 %sub151, %n.vec
  br i1 %cmp.n, label %while.after156, label %while.body155.preheader19

while.body155.preheader19:                        ; preds = %while.body155.preheader, %middle.block
  %storemerge17.ph = phi i32 [ 0, %while.body155.preheader ], [ %n.vec, %middle.block ]
  br label %while.body155

while.body155:                                    ; preds = %while.body155.preheader19, %while.body155
  %storemerge17 = phi i32 [ %add172, %while.body155 ], [ %storemerge17.ph, %while.body155.preheader19 ]
  %add165 = add i32 %add146, %storemerge17
  %22 = sext i32 %add165 to i64
  %idxgep = getelementptr [20 x i8], ptr %arr, i64 0, i64 %22
  %idxval = load i8, ptr %idxgep, align 1
  %idx64 = zext nneg i32 %storemerge17 to i64
  %ptradd = add i64 %asmres.i, %idx64
  %typedptr = inttoptr i64 %ptradd to ptr
  store i8 %idxval, ptr %typedptr, align 1
  %add172 = add nuw nsw i32 %storemerge17, 1
  %cmp159 = icmp slt i32 %add172, %sub151
  br i1 %cmp159, label %while.body155, label %while.after156, !llvm.loop !3

while.after156:                                   ; preds = %while.body155, %middle.block, %merge131
  %withfield = insertvalue { i32, i64 } undef, i32 %sub151, 0
  %withfield176 = insertvalue { i32, i64 } %withfield, i64 %asmres.i, 1
  ret { i32, i64 } %withfield176
}

define void @print__number(i32 %0) local_unnamed_addr {
entry:
  %arr.i = alloca [20 x i8], align 1
  call void @llvm.lifetime.start.p0(i64 20, ptr nonnull %arr.i)
  %gep68.i = getelementptr inbounds [20 x i8], ptr %arr.i, i64 0, i64 19
  %cmp.i = icmp slt i32 %0, 0
  %spec.select.i = tail call i32 @llvm.abs.i32(i32 %0, i1 false)
  %cmp80.i = icmp eq i32 %0, 0
  %spec.store.select.i = select i1 %cmp80.i, i8 48, i8 0
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(19) %arr.i, i8 0, i64 19, i1 false)
  store i8 %spec.store.select.i, ptr %gep68.i, align 1
  %spec.select12.i = select i1 %cmp80.i, i32 18, i32 19
  %cmp9713.i = icmp sgt i32 %spec.select.i, 0
  br i1 %cmp9713.i, label %while.body.i, label %while.after.i

while.body.i:                                     ; preds = %entry, %while.body.i
  %n.115.i = phi i32 [ %div.i, %while.body.i ], [ %spec.select.i, %entry ]
  %x69.114.i = phi i32 [ %sub114.i, %while.body.i ], [ %spec.select12.i, %entry ]
  %n.115.i.frozen = freeze i32 %n.115.i
  %div.i = udiv i32 %n.115.i.frozen, 10
  %1 = mul i32 %div.i, 10
  %rem.i.decomposed = sub i32 %n.115.i.frozen, %1
  %2 = sext i32 %x69.114.i to i64
  %stgep108.i = getelementptr [20 x i8], ptr %arr.i, i64 0, i64 %2
  %3 = trunc i32 %rem.i.decomposed to i8
  %sttrunc110.i = or disjoint i8 %3, 48
  store i8 %sttrunc110.i, ptr %stgep108.i, align 1
  %sub114.i = add i32 %x69.114.i, -1
  %cmp97.not.i = icmp ult i32 %n.115.i, 10
  br i1 %cmp97.not.i, label %while.after.i, label %while.body.i

while.after.i:                                    ; preds = %while.body.i, %entry
  %x69.1.lcssa.i = phi i32 [ %spec.select12.i, %entry ], [ %sub114.i, %while.body.i ]
  br i1 %cmp.i, label %then129.i, label %merge131.i

then129.i:                                        ; preds = %while.after.i
  %4 = sext i32 %x69.1.lcssa.i to i64
  %stgep134.i = getelementptr [20 x i8], ptr %arr.i, i64 0, i64 %4
  store i8 45, ptr %stgep134.i, align 1
  %sub140.i = add i32 %x69.1.lcssa.i, -1
  br label %merge131.i

merge131.i:                                       ; preds = %then129.i, %while.after.i
  %x69.2.i = phi i32 [ %sub140.i, %then129.i ], [ %x69.1.lcssa.i, %while.after.i ]
  %add146.i = add i32 %x69.2.i, 1
  %sub151.i = sub i32 19, %x69.2.i
  %argext.i = sext i32 %sub151.i to i64
  %asmres.i.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext.i, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp15916.i = icmp sgt i32 %sub151.i, 0
  br i1 %cmp15916.i, label %while.body155.i.preheader, label %numberToString.exit.thread

while.body155.i.preheader:                        ; preds = %merge131.i
  %min.iters.check = icmp ult i32 %sub151.i, 4
  %5 = add i32 %x69.2.i, 1
  %6 = icmp sgt i32 %5, 19
  %or.cond = or i1 %min.iters.check, %6
  br i1 %or.cond, label %while.body155.i.preheader18, label %vector.ph

vector.ph:                                        ; preds = %while.body155.i.preheader
  %n.vec = and i32 %sub151.i, 2147483644
  %broadcast.splatinsert = insertelement <4 x i64> poison, i64 %asmres.i.i, i64 0
  %broadcast.splat = shufflevector <4 x i64> %broadcast.splatinsert, <4 x i64> poison, <4 x i32> zeroinitializer
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %index = phi i32 [ 0, %vector.ph ], [ %index.next, %vector.body ]
  %vec.ind = phi <4 x i32> [ <i32 0, i32 1, i32 2, i32 3>, %vector.ph ], [ %vec.ind.next, %vector.body ]
  %7 = add i32 %add146.i, %index
  %8 = sext i32 %7 to i64
  %9 = getelementptr [20 x i8], ptr %arr.i, i64 0, i64 %8
  %wide.load = load <4 x i8>, ptr %9, align 1
  %10 = zext <4 x i32> %vec.ind to <4 x i64>
  %11 = add <4 x i64> %broadcast.splat, %10
  %12 = inttoptr <4 x i64> %11 to <4 x ptr>
  %13 = extractelement <4 x i8> %wide.load, i64 0
  %14 = extractelement <4 x ptr> %12, i64 0
  store i8 %13, ptr %14, align 1
  %15 = extractelement <4 x i8> %wide.load, i64 1
  %16 = extractelement <4 x ptr> %12, i64 1
  store i8 %15, ptr %16, align 1
  %17 = extractelement <4 x i8> %wide.load, i64 2
  %18 = extractelement <4 x ptr> %12, i64 2
  store i8 %17, ptr %18, align 1
  %19 = extractelement <4 x i8> %wide.load, i64 3
  %20 = extractelement <4 x ptr> %12, i64 3
  store i8 %19, ptr %20, align 1
  %index.next = add nuw i32 %index, 4
  %vec.ind.next = add <4 x i32> %vec.ind, <i32 4, i32 4, i32 4, i32 4>
  %21 = icmp eq i32 %index.next, %n.vec
  br i1 %21, label %middle.block, label %vector.body, !llvm.loop !4

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i32 %sub151.i, %n.vec
  br i1 %cmp.n, label %numberToString.exit, label %while.body155.i.preheader18

while.body155.i.preheader18:                      ; preds = %while.body155.i.preheader, %middle.block
  %storemerge17.i.ph = phi i32 [ 0, %while.body155.i.preheader ], [ %n.vec, %middle.block ]
  br label %while.body155.i

numberToString.exit.thread:                       ; preds = %merge131.i
  call void @llvm.lifetime.end.p0(i64 20, ptr nonnull %arr.i)
  %add.i12 = sub i32 20, %x69.2.i
  %argext.i513 = sext i32 %add.i12 to i64
  %asmres.i.i614 = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext.i513, i64 3, i64 34, i64 -1, i64 0) #6
  br label %print__String.exit

while.body155.i:                                  ; preds = %while.body155.i.preheader18, %while.body155.i
  %storemerge17.i = phi i32 [ %add172.i, %while.body155.i ], [ %storemerge17.i.ph, %while.body155.i.preheader18 ]
  %add165.i = add i32 %add146.i, %storemerge17.i
  %22 = sext i32 %add165.i to i64
  %idxgep.i = getelementptr [20 x i8], ptr %arr.i, i64 0, i64 %22
  %idxval.i = load i8, ptr %idxgep.i, align 1
  %idx64.i = zext nneg i32 %storemerge17.i to i64
  %ptradd.i = add i64 %asmres.i.i, %idx64.i
  %typedptr.i = inttoptr i64 %ptradd.i to ptr
  store i8 %idxval.i, ptr %typedptr.i, align 1
  %add172.i = add nuw nsw i32 %storemerge17.i, 1
  %cmp159.i = icmp slt i32 %add172.i, %sub151.i
  br i1 %cmp159.i, label %while.body155.i, label %numberToString.exit, !llvm.loop !5

numberToString.exit:                              ; preds = %while.body155.i, %middle.block
  call void @llvm.lifetime.end.p0(i64 20, ptr nonnull %arr.i)
  %add.i = sub i32 20, %x69.2.i
  %argext.i5 = sext i32 %add.i to i64
  %asmres.i.i6 = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext.i5, i64 3, i64 34, i64 -1, i64 0) #6
  br i1 %cmp15916.i, label %while.body.i8, label %print__String.exit

while.body.i8:                                    ; preds = %numberToString.exit, %while.body.i8
  %x12.016.i = phi i32 [ %add25.i, %while.body.i8 ], [ 0, %numberToString.exit ]
  %idx64.i.i = zext nneg i32 %x12.016.i to i64
  %ptradd.i.i = add i64 %asmres.i.i, %idx64.i.i
  %typedptr.i.i = inttoptr i64 %ptradd.i.i to ptr
  %typedval.i.i = load i8, ptr %typedptr.i.i, align 1
  %ptradd.i9 = add i64 %asmres.i.i6, %idx64.i.i
  %typedptr.i10 = inttoptr i64 %ptradd.i9 to ptr
  store i8 %typedval.i.i, ptr %typedptr.i10, align 1
  %add25.i = add nuw nsw i32 %x12.016.i, 1
  %cmp.i11 = icmp slt i32 %add25.i, %sub151.i
  br i1 %cmp.i11, label %while.body.i8, label %print__String.exit

print__String.exit:                               ; preds = %while.body.i8, %numberToString.exit.thread, %numberToString.exit
  %asmres.i.i616 = phi i64 [ %asmres.i.i614, %numberToString.exit.thread ], [ %asmres.i.i6, %numberToString.exit ], [ %asmres.i.i6, %while.body.i8 ]
  %argext.i515 = phi i64 [ %argext.i513, %numberToString.exit.thread ], [ %argext.i5, %numberToString.exit ], [ %argext.i5, %while.body.i8 ]
  %ptradd35.i = add i64 %asmres.i.i616, %argext.i
  %typedptr36.i = inttoptr i64 %ptradd35.i to ptr
  store i8 10, ptr %typedptr36.i, align 1
  tail call void asm sideeffect "syscall", "{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 1, i64 1, i64 %asmres.i.i616, i64 %argext.i515) #6
  tail call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %asmres.i.i616, i64 %argext.i515) #6
  tail call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %asmres.i.i, i64 %argext.i) #6
  ret void
}

define i64 @alloc(i64 %0) local_unnamed_addr {
entry:
  %asmres = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %0, i64 3, i64 34, i64 -1, i64 0) #6
  ret i64 %asmres
}

define void @free(i64 %0, i64 %1) local_unnamed_addr {
entry:
  tail call void asm sideeffect "syscall", "{rax},{rdi},{rsi},~{rcx},~{r11},~{memory}"(i64 11, i64 %0, i64 %1) #6
  ret void
}

define { i32, i64 } @readLine() local_unnamed_addr {
entry:
  %arr = alloca [1024 x i8], align 1
  %ptrint = ptrtoint ptr %arr to i64
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(1024) %arr, i8 0, i64 1024, i1 false)
  %asmres = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory}"(i64 0, i64 0, i64 %ptrint, i64 1024) #6
  %cmp = icmp sgt i64 %asmres, 0
  %extract.t5 = trunc i64 %asmres to i32
  br i1 %cmp, label %then, label %merge

then:                                             ; preds = %entry
  %sub = add nsw i64 %asmres, -1
  %idxgep = getelementptr [1024 x i8], ptr %arr, i64 0, i64 %sub
  %idxval = load i8, ptr %idxgep, align 1
  %cmp3096 = icmp eq i8 %idxval, 10
  %extract.t = trunc i64 %sub to i32
  %spec.select = select i1 %cmp3096, i32 %extract.t, i32 %extract.t5
  br label %merge

merge:                                            ; preds = %then, %entry
  %asmout.0.off0 = phi i32 [ %extract.t5, %entry ], [ %spec.select, %then ]
  %withfield = insertvalue { i32, i64 } undef, i32 %asmout.0.off0, 0
  %withfield3113 = insertvalue { i32, i64 } %withfield, i64 %ptrint, 1
  ret { i32, i64 } %withfield3113
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none)
define i8 @charAt({ i32, i64 } %0, i32 %1) local_unnamed_addr #1 {
entry:
  %.fca.1.extract = extractvalue { i32, i64 } %0, 1
  %idx64 = sext i32 %1 to i64
  %ptradd = add i64 %.fca.1.extract, %idx64
  %typedptr = inttoptr i64 %ptradd to ptr
  %typedval = load i8, ptr %typedptr, align 1
  ret i8 %typedval
}

define i64 @toCstr({ i32, i64 } %0) local_unnamed_addr {
entry:
  %.fca.0.extract = extractvalue { i32, i64 } %0, 0
  %add = add i32 %.fca.0.extract, 1
  %argext = sext i32 %add to i64
  %asmres.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp12 = icmp sgt i32 %.fca.0.extract, 0
  br i1 %cmp12, label %while.body.lr.ph, label %while.after

while.body.lr.ph:                                 ; preds = %entry
  %.fca.1.extract.i = extractvalue { i32, i64 } %0, 1
  br label %while.body

while.body:                                       ; preds = %while.body.lr.ph, %while.body
  %x12.013 = phi i32 [ 0, %while.body.lr.ph ], [ %add25, %while.body ]
  %idx64.i = zext nneg i32 %x12.013 to i64
  %ptradd.i = add i64 %.fca.1.extract.i, %idx64.i
  %typedptr.i = inttoptr i64 %ptradd.i to ptr
  %typedval.i = load i8, ptr %typedptr.i, align 1
  %ptradd = add i64 %asmres.i, %idx64.i
  %typedptr = inttoptr i64 %ptradd to ptr
  store i8 %typedval.i, ptr %typedptr, align 1
  %add25 = add nuw nsw i32 %x12.013, 1
  %cmp = icmp slt i32 %add25, %.fca.0.extract
  br i1 %cmp, label %while.body, label %while.after

while.after:                                      ; preds = %while.body, %entry
  %idx6433 = sext i32 %.fca.0.extract to i64
  %ptradd35 = add i64 %asmres.i, %idx6433
  %typedptr36 = inttoptr i64 %ptradd35 to ptr
  store i8 0, ptr %typedptr36, align 1
  ret i64 %asmres.i
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none)
define noundef i1 @strEq({ i32, i64 } %0, { i32, i64 } %1) local_unnamed_addr #2 {
entry:
  %.fca.0.extract3 = extractvalue { i32, i64 } %0, 0
  %.fca.0.extract = extractvalue { i32, i64 } %1, 0
  %cmp.not = icmp eq i32 %.fca.0.extract3, %.fca.0.extract
  br i1 %cmp.not, label %while.cond.preheader, label %common.ret

while.cond.preheader:                             ; preds = %entry
  %.fca.1.extract.i = extractvalue { i32, i64 } %0, 1
  %cmp2114 = icmp sgt i32 %.fca.0.extract3, 0
  br i1 %cmp2114, label %while.body.lr.ph, label %common.ret

while.body.lr.ph:                                 ; preds = %while.cond.preheader
  %.fca.1.extract.i9 = extractvalue { i32, i64 } %1, 1
  br label %while.body

common.ret:                                       ; preds = %while.body, %while.cond.preheader, %entry
  %common.ret.op = phi i1 [ false, %entry ], [ true, %while.cond.preheader ], [ %cmp30.not, %while.body ]
  ret i1 %common.ret.op

while.body:                                       ; preds = %while.body, %while.body.lr.ph
  %storemerge15 = phi i32 [ 0, %while.body.lr.ph ], [ %add, %while.body ]
  %idx64.i = zext nneg i32 %storemerge15 to i64
  %ptradd.i = add i64 %.fca.1.extract.i, %idx64.i
  %typedptr.i = inttoptr i64 %ptradd.i to ptr
  %typedval.i = load i8, ptr %typedptr.i, align 1
  %ptradd.i11 = add i64 %.fca.1.extract.i9, %idx64.i
  %typedptr.i12 = inttoptr i64 %ptradd.i11 to ptr
  %typedval.i13 = load i8, ptr %typedptr.i12, align 1
  %cmp30.not = icmp eq i8 %typedval.i, %typedval.i13
  %add = add nuw nsw i32 %storemerge15, 1
  %cmp21 = icmp slt i32 %add, %.fca.0.extract3
  %or.cond = select i1 %cmp30.not, i1 %cmp21, i1 false
  br i1 %or.cond, label %while.body, label %common.ret
}

define { i32, i64 } @strConcat({ i32, i64 } %0, { i32, i64 } %1) local_unnamed_addr {
entry:
  %.fca.0.extract11 = extractvalue { i32, i64 } %0, 0
  %.fca.0.extract = extractvalue { i32, i64 } %1, 0
  %add = add i32 %.fca.0.extract, %.fca.0.extract11
  %argext = sext i32 %add to i64
  %asmres.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp24 = icmp sgt i32 %.fca.0.extract11, 0
  br i1 %cmp24, label %while.body.lr.ph, label %while.cond30.preheader

while.body.lr.ph:                                 ; preds = %entry
  %.fca.1.extract.i = extractvalue { i32, i64 } %0, 1
  br label %while.body

while.cond30.preheader:                           ; preds = %while.body, %entry
  %cmp3926 = icmp sgt i32 %.fca.0.extract, 0
  br i1 %cmp3926, label %while.body31.lr.ph, label %while.after32

while.body31.lr.ph:                               ; preds = %while.cond30.preheader
  %.fca.1.extract.i19 = extractvalue { i32, i64 } %1, 1
  br label %while.body31

while.body:                                       ; preds = %while.body.lr.ph, %while.body
  %x14.025 = phi i32 [ 0, %while.body.lr.ph ], [ %add27, %while.body ]
  %idx64.i = zext nneg i32 %x14.025 to i64
  %ptradd.i = add i64 %.fca.1.extract.i, %idx64.i
  %typedptr.i = inttoptr i64 %ptradd.i to ptr
  %typedval.i = load i8, ptr %typedptr.i, align 1
  %ptradd = add i64 %asmres.i, %idx64.i
  %typedptr = inttoptr i64 %ptradd to ptr
  store i8 %typedval.i, ptr %typedptr, align 1
  %add27 = add nuw nsw i32 %x14.025, 1
  %cmp = icmp slt i32 %add27, %.fca.0.extract11
  br i1 %cmp, label %while.body, label %while.cond30.preheader

while.body31:                                     ; preds = %while.body31.lr.ph, %while.body31
  %storemerge27 = phi i32 [ 0, %while.body31.lr.ph ], [ %add64, %while.body31 ]
  %idx64.i20 = zext nneg i32 %storemerge27 to i64
  %ptradd.i21 = add i64 %.fca.1.extract.i19, %idx64.i20
  %typedptr.i22 = inttoptr i64 %ptradd.i21 to ptr
  %typedval.i23 = load i8, ptr %typedptr.i22, align 1
  %add52 = add i32 %storemerge27, %.fca.0.extract11
  %idx6456 = sext i32 %add52 to i64
  %ptradd58 = add i64 %asmres.i, %idx6456
  %typedptr59 = inttoptr i64 %ptradd58 to ptr
  store i8 %typedval.i23, ptr %typedptr59, align 1
  %add64 = add nuw nsw i32 %storemerge27, 1
  %cmp39 = icmp slt i32 %add64, %.fca.0.extract
  br i1 %cmp39, label %while.body31, label %while.after32

while.after32:                                    ; preds = %while.body31, %while.cond30.preheader
  %withfield = insertvalue { i32, i64 } undef, i32 %add, 0
  %withfield68 = insertvalue { i32, i64 } %withfield, i64 %asmres.i, 1
  ret { i32, i64 } %withfield68
}

define { i32, i64 } @substr({ i32, i64 } %0, i32 %1, i32 %2) local_unnamed_addr {
entry:
  %argext = sext i32 %2 to i64
  %asmres.i = tail call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 9, i64 0, i64 %argext, i64 3, i64 34, i64 -1, i64 0) #6
  %cmp7 = icmp sgt i32 %2, 0
  br i1 %cmp7, label %while.body.lr.ph, label %while.after

while.body.lr.ph:                                 ; preds = %entry
  %.fca.1.extract.i = extractvalue { i32, i64 } %0, 1
  br label %while.body

while.body:                                       ; preds = %while.body.lr.ph, %while.body
  %x11.08 = phi i32 [ 0, %while.body.lr.ph ], [ %add21, %while.body ]
  %add = add i32 %x11.08, %1
  %idx64.i = sext i32 %add to i64
  %ptradd.i = add i64 %.fca.1.extract.i, %idx64.i
  %typedptr.i = inttoptr i64 %ptradd.i to ptr
  %typedval.i = load i8, ptr %typedptr.i, align 1
  %idx64 = zext nneg i32 %x11.08 to i64
  %ptradd = add i64 %asmres.i, %idx64
  %typedptr = inttoptr i64 %ptradd to ptr
  store i8 %typedval.i, ptr %typedptr, align 1
  %add21 = add nuw nsw i32 %x11.08, 1
  %cmp = icmp slt i32 %add21, %2
  br i1 %cmp, label %while.body, label %while.after

while.after:                                      ; preds = %while.body, %entry
  %withfield = insertvalue { i32, i64 } undef, i32 %2, 0
  %withfield24 = insertvalue { i32, i64 } %withfield, i64 %asmres.i, 1
  ret { i32, i64 } %withfield24
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define void @plus() local_unnamed_addr #0 {
entry:
  ret void
}

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.abs.i32(i32, i1 immarg) #3

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr nocapture writeonly, i8, i64, i1 immarg) #4

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #5

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #5

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(none) }
attributes #1 = { mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none) }
attributes #2 = { nofree norecurse nosync nounwind memory(read, inaccessiblemem: none) }
attributes #3 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #4 = { nocallback nofree nounwind willreturn memory(argmem: write) }
attributes #5 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
attributes #6 = { nounwind }

!0 = distinct !{!0, !1, !2}
!1 = !{!"llvm.loop.isvectorized", i32 1}
!2 = !{!"llvm.loop.unroll.runtime.disable"}
!3 = distinct !{!3, !1}
!4 = distinct !{!4, !1, !2}
!5 = distinct !{!5, !1}
