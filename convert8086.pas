(* convert 8086-8088 opcodes to mnemonics
   copyright (c) 2017 by ir. Marc Dendooven *)

program convert8086;

const 	mnem00 : array[0..7] of string = ('ADD','OR','ADC','SSB','AND','SUB','XOR','CMP');
		mnem010: array[0..3] of string = ('INC','DEC','PUSH','POP');
		reg010 : array[0..7] of string = ('AX','CX','DX','BX','SP','BP','SI','DI');
		regByte: array[0..7] of string = ('AL','CL','DL','BL','AH','CH','DH','BH');
		cond0111 : array[0..15] of string = ('O','NO','B','NB','Z','NZ','BE','A','S','NS','PE','PO','PL','GE','LE','G');
		
		
var i: byte;



procedure dis(opc: byte);

	procedure regular00;
	begin
		if (opc and %00000110) = %110 
			then writeln ('nyi')
			else
				begin
					write(mnem00[(opc and %00111000)>>3]);
					if (opc and %00000100) = 0 then write(' E,G') else write (' A,I');
					if (opc and %00000010) <>0 then write (' (reverse)');
					if (opc and %00000001) = 0 then writeln ('(b)') else writeln('(w)')
				end
	end;
	
	procedure regular010;
	begin
		writeln (mnem010[(opc and %00011000)>>3],' ',reg010[opc and %00000111])
	end;
	
	procedure regular0111;
	begin
		writeln ('J',cond0111[opc and %00001111])
	end;
	
	procedure xchg;
	begin
		if opc = $90 then writeln('NOP') else writeln('XCHG ',reg010[opc and %00000111],' AX')
	end;
	
	procedure movIb;
	begin
		writeln('MOV ',regByte[opc and %00000111],' Ib')
	end;
	
	procedure movIv;
	begin
		writeln('MOV ',reg010[opc and %00000111],' Iv')
	end;

begin
	if (opc and %11000000) = 0 then regular00	
	else if (opc and %11100000) = %01000000 then regular010	
	else if (opc and %11110000) = %01100000 then writeln('illegal instruction')
	else if (opc and %11110000) = %01110000 then regular0111
	else if (opc and %11111000) = %10000000 then writeln('nyi - irregular')
	else if (opc and %11111000) = %10001000 then writeln('mov81')
	else if (opc and %11111000) = %10010000 then xchg
	else if (opc and %11111000) = %10011000 then writeln('nyi - irregular')
	else if (opc and %11111000) = %10100000 then writeln('movA0')
	else if (opc and %11111000) = %10101000 then writeln('nyi - irregular')
	else if (opc and %11111000) = %10110000 then movIb
	else if (opc and %11111000) = %10111000 then movIv
	else writeln('nyi or illegal instruction')
end;


begin
	for i:=0 to 255 do begin write(hexstr(i,2),':'); dis(i) end
end.
