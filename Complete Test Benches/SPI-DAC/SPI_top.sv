 module spiDAC(
input clk, enable,reset,
input [11:0] din, 
output reg SCLK,CS,MOSI
    );
  
parameter IDLE = 2'b00, TX = 2'b01;   
reg [1:0] STATE;
int clk_count = 0;
int d_index = 0;

/////////////////////////generation of SCLK
always@(posedge clk)
begin
if(reset == 1'b1) begin
    clk_count <= 0;
    SCLK <= 1'b0;
end
else begin 
    if(clk_count < 50 )
        clk_count <= clk_count + 1;
    else
        begin
        clk_count <= 0;
        SCLK <= ~SCLK;
        end
end
end

//////////////////STATE machine
reg [11:0] temp;

always@(posedge SCLK)
begin
if(reset == 1'b1) begin
    CS <= 1'b1; 
    MOSI <= 1'b0;
end
else begin
    case(STATE)
        IDLE:
            begin
            if(enable == 1'b1) begin
                STATE <= TX;
                temp <= din; 
                CS <= 1'b0;
            end
            else begin
                STATE <= IDLE;
                temp <= 8'd0;
            end
            end
    
    
    TX : begin
        if(d_index <= 11) begin
        MOSI <= temp[d_index]; /////TXing lsb first
        d_index <= d_index + 1;
        end
        else
            begin
            d_index <= 0;
            STATE <= IDLE;
            CS <= 1'b1;
            MOSI <= 1'b0;
            end
    end
    
            
    default : STATE <= IDLE; 
    
endcase
end 
end

endmodule
///////////////////////////

interface spiDAC_if;


logic clk;
logic enable;
logic reset;
logic [11:0] din;
logic SCLK;
logic CS;
logic MOSI;


endinterface