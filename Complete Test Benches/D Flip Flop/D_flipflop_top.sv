module dff(dff_if dif);                 //You can design the DUT with the interface in mind and it can greatly simplifiy port mapping


    always @(posedge dif.clk) begin
        if(dif.reset == 1'b1)
            dif.dout <= 1'b0;
        else 
            dif.dout <= dif.din;  
    end





endmodule

interface dff_if;
    logic clk;
    logic reset;
    logic din;
    logic dout;
endinterface