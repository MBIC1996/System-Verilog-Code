////////////////////    Transaction     ////////////////////

class transaction;

    rand bit din;
    bit dout;
    
    function void display(input string tag);
        $display("[%0s] DATA IN :   %0b \t DATA OUT :   %0b",tag,din,dout);
    endfunction

    function transaction copy();
        copy = new();
        copy.din = this.din;
        copy.dout = this.dout;
    endfunction 

endclass

////////////////////    Generator     ////////////////////

class generator;

transaction tr;
mailbox #(transaction) mbx;
int count;
event next;
event done;

    function new(mailbox #(transaction) mbx);
        tr = new();
        this.mbx = mbx;
    endfunction

    task main();
            repeat(count)
                begin
                    assert(tr.randomize) else $error("[GEN] RANDOMIZATION FAILED AT %0t",$time);
                    mbx.put(tr.copy);
                    tr.display("GEN");
                    @(next);
                end
            ->done;
            
    endtask

endclass
                
////////////////////    Driver     ///////////////////////

class driver;

mailbox #(transaction) mbx;
transaction stimulus;
virtual dff_if dif;


    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task reset();

        dif.reset <= 1'b1;
        repeat(5) @(posedge dif.clk);

        dif.reset <= 1'b0;

         @(posedge dif.clk);

        $display("[DRV] DUT RESET APPLIED");

    endtask

    task main();
        forever begin

            mbx.get(stimulus);
            dif.din <= stimulus.din;
            stimulus.display("DRV");
            @(posedge dif.clk);
        end
    endtask

endclass
        
         
////////////////////    Monitor    ///////////////////////

class monitor;

virtual dff_if dif;

transaction response;
mailbox #(transaction) mbx;

   function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task main();
        response = new();

        forever begin
            @(posedge dif.clk);
            @(posedge dif.clk);

            response.dout = dif.dout;

            mbx.put(response);
            response.display("MON");
        end
    endtask

endclass


////////////////////    Scoreboard     ///////////////////////
class scoreboard;

transaction tr;
mailbox #(transaction) mbx;
event next;


    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task main();
        forever begin
            mbx.get(tr);             //get transaction from mailbox and but in container tr
            tr.display("SCO");
            if(tr.din == tr.dout) begin //This wont work
                $display("[SCO] : DATA MATCHED");
            end
            else begin
                $display("[SCO] : DATA MISMATCH");
            end

            
            ->next;
        end
    endtask

endclass


////////////////////    Environment     ///////////////////////

class environment;

generator gen;
driver drv;
monitor mon;
scoreboard sco;

event next;

mailbox #(transaction) mbxgd;   //generator driver mbx
mailbox #(transaction) mbxms;   //monitor scoreboard mbx

virtual dff_if dif;

    function new(virtual dff_if dif);
        mbxgd = new();
        gen = new(mbxgd);
        drv = new(mbxgd);

        mbxms = new();
        mon = new(mbxms);
        sco = new(mbxms);

        this.dif = dif;
        drv.dif = dif;
        mon.dif= dif;

        gen.next = this.next;
        sco.next = this.next;


    endfunction

    task pre_test();
        drv.reset();
    endtask

    task test();
        fork
            gen.main();
            drv.main();
            mon.main();
            sco.main();
        join_any
    endtask

    task post_test();
        wait(gen.done.triggered);
        $finish();
    endtask

    task main();
        pre_test();
        test();
        post_test();
    endtask
endclass

////////////////////    TEST BENCH TOP     ///////////////////////


module tb();

dff_if dif();

dff DUT(dif);

    initial begin
        dif.clk <= 1'b0;;
    end

    always #10 dif.clk <= ~dif.clk;

environment env;

    initial begin
        env = new(dif);
        env.gen.count = 20;
        env.main();
    end 

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end


endmodule





            











